# add this report in your puppetmaster reports - e.g, in your puppet.conf add:
#     reports = log, foreman # (or any other reports you want)
#     reporturl = https://foreman.example.org
#
# You can also configure via /etc/puppet/foreman.yaml
#
require 'puppet'

Puppet::Reports.register_report(:foreman) do
  desc "Sends reports directly to Foreman"

  SETTINGS_FILE = File.join(Puppet.settings[:confdir], 'foreman.yaml')
  if File.exist? SETTINGS_FILE
    SETTINGS = YAML.load_file(SETTINGS_FILE)
  else
    SETTINGS = {url: Puppet.settings.set_by_config?(:reporturl) ?
      Puppet.settings[:reporturl] : "https://#{Puppet.settings[:report_server]}"
    }
  end

  def process
    begin
      # check for report metrics
      raise(Puppet::ParseError, "Invalid report: can't find metrics information for #{self.host}") if self.metrics.nil?

      uri = URI.parse(foreman_url)
      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json,version=2',
      }
      # This metric_id option is silently ignored by Puppet's http client
      # (Puppet::Network::HTTP) but is used by Puppet Server's http client
      # (Puppet::Server::HttpClient) to track metrics on the request made to the
      # `reporturl` to store a report.
      options = {
        metric_id: [:puppet, :report, :http],
        include_system_store: Puppet[:report_include_system_store],
      }

      # # Is customizing this client separately valuable? Do people actually /do/ it?
      # # puppet.conf already allows all this to be customized in a single place
      # # and specifying these means we create a new pool each time.
      # #
      # # Default retry limit is 1.
      # retry_limit = SETTINGS.fetch(:report_retry_limit, 1)
      # client = Puppet::HTTP::Client.new(
      #   pool: Puppet::HTTP::Pool.new(SETTINGS[:report_timeout]),
      #   retry_limit: retry_limit,
      #   ssl_context: Puppet::SSL::SSLContext.new(
      #                   cacerts: SETTINGS[:ssl_ca],
      #                   client_cert: SETTINGS[:ssl_cert],
      #                   private_key: SETTINGS[:ssl_key],
      #                 ))

      uri.path += '/api/config_reports'
      body = {config_report: generate_report}.to_json
      client = Puppet.runtime[:http]
      client.post(uri, body, headers: headers, options: options) do |response|
        unless response.success?
          Puppet.err "HTTP request failed with code: #{response.code} body: #{response.reason}"
        end
      end
    rescue Exception => e
      Puppet.err "Could not send report to Foreman at #{foreman_url}/api/config_reports: #{e}\n#{e.backtrace}"
    end
  end

  def generate_report
    {
      'host' => self.host,
      'reported_at' => self.time.utc.to_s,
      'status' => metrics_to_hash(self),
      'metrics' => m2h(self.metrics),
      'logs' => logs_to_array(self.logs),
    }
  end

  private

  METRIC = %w[applied restarted failed failed_restarts skipped pending]

  def metrics_to_hash(report)
    report_status = {}
    metrics = self.metrics

    # find our metric values
    METRIC.each do |m|
      case m
      when "applied"
        mv = metrics["changes"]
        name = "total"
      when "failed_restarts"
        mv = metrics["resources"]
        name = "failed_to_restart"
      when "pending"
        mv = metrics["events"]
        name = "noop"
      else
        mv = metrics["resources"]
        name = m
      end
      report_status[m] = mv[name.to_sym] + mv[name.to_s] rescue nil
      report_status[m] ||= 0
    end

    # special fix for false warning about skips
    # sometimes there are skip values, but there are no error messages, we ignore them.
    if report_status["skipped"] > 0 and ((report_status.values.inject(:+)) - report_status["skipped"] == report.logs.size)
      report_status["skipped"] = 0
    end
    # fix for reports that contain no metrics (i.e. failed catalog)
    if report.respond_to?(:status) and report.status == "failed"
      report_status["failed"] += 1
    end
    # fix for Puppet non-resource errors (i.e. failed catalog fetches before falling back to cache)
    report_status["failed"] += report.logs.count {|l| l.source =~ /Puppet$/ && l.level.to_s == 'err' }

    return report_status
  end

  def m2h metrics
    metrics.transform_values do |mtype|
      mtype.values.to_h { |name, _label, value| [name, value] }
    end
  end

  def logs_to_array logs
    h = []
    logs.each do |log|
      # skipping debug messages, we don't want them in Foreman's db
      next if log.level == :debug

      # skipping catalog summary run messages, we don't want them in Foreman's db
      next if log.message =~ /^Finished catalog run in \d+.\d+ seconds$/

      # Match Foreman's slightly odd API format...
      h << {
        'log' => {
          'level' => log.level.to_s,
          'sources' => {
            'source' => log.source,
          },
          'messages' => {
            'message' => log.message,
          },
        },
      }
    end
    return h
  end

  def foreman_url
    SETTINGS[:url] || raise(Puppet::Error, "Must provide URL in #{SETTINGS_FILE}")
  end

end
