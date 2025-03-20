# copy this file to your report dir - e.g. /usr/lib/ruby/1.8/puppet/reports/
# add this report in your puppetmaster reports - e.g, in your puppet.conf add:
# reports=log, foreman # (or any other reports you want)
# configuration is in /etc/puppet/foreman.yaml

require 'puppet'
require 'net/http'
require 'net/https'
require 'rbconfig'
require 'uri'
require 'yaml'
begin
  require 'json'
rescue LoadError
  # Debian packaging guidelines state to avoid needing rubygems, so
  # we only try to load it if the first require fails (for RPMs)
  begin
    require 'rubygems' rescue nil
    require 'json'
  rescue LoadError => e
    puts "You need the `json` gem to use the Foreman ENC script"
    # code 1 is already used below
    exit 2
  end
end

if RbConfig::CONFIG['host_os'] =~ /freebsd|dragonfly/i
  $settings_file ||= '/usr/local/etc/puppet/foreman.yaml'
else
  $settings_file ||= File.exist?('/etc/puppetlabs/puppet/foreman.yaml') ? '/etc/puppetlabs/puppet/foreman.yaml' : '/etc/puppet/foreman.yaml'
end

SETTINGS = YAML.load_file($settings_file)

Puppet::Reports.register_report(:foreman) do
  desc "Sends reports directly to Foreman"

  def process
    # Default retry limit is 1.
    retry_limit = SETTINGS.fetch(:report_retry_limit, 1)
    tries = 0
    begin
      # check for report metrics
      raise(Puppet::ParseError, "Invalid report: can't find metrics information for #{self.host}") if self.metrics.nil?

      uri = URI.parse(foreman_url)
      http = Net::HTTP.new(uri.host, uri.port)
      if SETTINGS[:report_timeout]
        http.open_timeout = SETTINGS[:report_timeout]
        http.read_timeout = SETTINGS[:report_timeout]
      end
      http.use_ssl     = uri.scheme == 'https'
      if http.use_ssl?
        if SETTINGS[:ssl_ca] && !SETTINGS[:ssl_ca].empty?
          http.ca_file = SETTINGS[:ssl_ca]
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        if SETTINGS[:ssl_cert] && !SETTINGS[:ssl_cert].empty? && SETTINGS[:ssl_key] && !SETTINGS[:ssl_key].empty?
          http.cert = OpenSSL::X509::Certificate.new(File.read(SETTINGS[:ssl_cert]))
          http.key  = OpenSSL::PKey::RSA.new(File.read(SETTINGS[:ssl_key]), nil)
        end
      end
      req = Net::HTTP::Post.new("#{uri.path}/api/config_reports")
      req.add_field('Accept', 'application/json,version=2' )
      req.content_type = 'application/json'
      req.body         = {'config_report' => generate_report}.to_json
      response = http.request(req)
    rescue Exception => e
      if (tries += 1) < retry_limit
        Puppet.err "Could not send report to Foreman at #{foreman_url}/api/config_reports (attempt #{tries}/#{retry_limit}). Retrying... Stacktrace: #{e}\n#{e.backtrace}"
        retry
      else
        raise Puppet::Error, "Could not send report to Foreman at #{foreman_url}/api/config_reports: #{e}\n#{e.backtrace}"
      end
    end
  end

  def generate_report
    {
      'host' => self.host,
      # Time.to_s behaves differently in 1.8 / 1.9 so we explicity set the 1.9 format
      'reported_at' => self.time.utc.strftime("%Y-%m-%d %H:%M:%S UTC"),
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
    logs.filter_map do |log|
      # skipping debug messages, we dont want them in Foreman's db
      next if log.level == :debug

      # skipping catalog summary run messages, we dont want them in Foreman's db
      next if log.message =~ /^Finished catalog run in \d+.\d+ seconds$/

      # Match Foreman's slightly odd API format...
      {
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
  end

  def foreman_url
    SETTINGS[:url] || raise(Puppet::Error, "Must provide URL in #{$settings_file}")
  end

end
