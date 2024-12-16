#!/usr/bin/env ruby

# Script usually acts as an ENC for a single host, with the certname supplied as argument
#   if 'facts' is true, the YAML facts for the host are uploaded
#   ENC output is printed and cached
#
# If --push-facts is given as the only arg, it uploads facts for all hosts and then exits.
# Useful in scenarios where the ENC isn't used.

require 'etc'
require 'fileutils'
require 'json'
require 'net/http'
require 'net/https'
require 'rbconfig'
require 'timeout'
require 'yaml'

# TODO: still needed?
Encoding.default_external = Encoding::UTF_8

class FactUploadError < StandardError; end
class NodeRetrievalError < StandardError; end

class Settings
  class << self
    def settings_file
      if RbConfig::CONFIG['host_os'] =~ /freebsd|dragonfly/i
        '/usr/local/etc/puppet/foreman.yaml'
      elsif File.exist?('/etc/puppetlabs/puppet/foreman.yaml')
        '/etc/puppetlabs/puppet/foreman.yaml'
      else
        '/etc/puppet/foreman.yaml'
      end
    end

    SETTINGS = new(settings_file)
  end

  def initialize(path)
    @settings = YAML.load_file(path)
    @settings.delete_if! { |_key, value| value.respond_to(:empty?) && value.empty? }
  end

  def url
    @settings[:url] || raise("Must provide URL in #{settings_file}")
  end

  def puppet_dir
    @settings[:puppetdir] || raise("Must provide puppet base directory in #{settings_file}")
  end

  def puppet_user
    @settings.fetch(:puppetuser, 'puppet')
  end

  def fact_extension
    @settings.fetch(:fact_extension, 'yaml')
  end

  def facts?
    @settings[:facts]
  end

  def ssl_ca
    @settings[:ssl_ca]
  end

  def ssl_cert
    @settings[:ssl_cert]
  end

  def ssl_key
    @settings[:ssl_key]
  end

  def stat_dir
    File.join(Settings.puppet_dir, 'yaml', 'foreman')
  end

  def timeout
    @settings[:timeout]
  end

  def threads
    if @settings[:threads].to_i > 0
      @settings[:threads].to_i
    else
      require 'facter'
      max(Facter.value(:processorcount).to_i, 1)
    end
  end
end

class Facts
  class << self
    EXTENSION = Settings.fact_extension

    def directory
      data_dir = EXTENSION == 'yaml' ? 'yaml' : 'server_data'
      File.join(Settings.puppet_dir, data_dir, 'facts')
    end

    def file(certname)
      File.join(directory, "#{certname}.#{EXTENSION}")
    end

    def files
      Dir[File.join(directory, "*.#{EXTENSION}")]
    end

    def certname_from_filename(filename)
      File.basename(filename, ".#{EXTENSION}")
    end
  end
end

class Cache
  INSTANCE = new(Settings.stat_dir)

  def initialize(directory)
    @directory = directory
  end

  def write(key, result)
    FileUtils.mkdir_p(@directory)
    File.write(path(key), result)
  end

  def read(key)
    File.read(path(key))
  rescue StandardError => e
    raise "Unable to read from Cache file: #{e}"
  end

  def fresh?(key, mtime)
    File.stat(path(key)).mtime.utc >= mtime.utc
  rescue Errno::ENOENT
    false
  end

  private

  def path(key)
    File.join(@directory, "#{key}.yaml")
  end
end

class ForemanClient
  attr_reader :base_url

  def initialize(base_url)
    @base_url = base_url
  end

  def upload_facts(certname, filename = nil)
    filename ||= Fact.file(certname)
    begin
      stat = File.stat(filename)
    rescue Errno::ENOENT
      warn "Fact file #{filename} does not exist"
    end

    unless stat.size?
      warn "Fact file #{filename} does not contain any facts"
      return
    end

    cache_name = cache_key(certname)
    return if Cache::INSTANCE.fresh?(cache_name, stat)

    unless (body = build_fact_body(certname, filename))
      warn "Empty values hash in fact file #{filename}, not uploading"
      return
    end

    uri = URI.parse("#{base_url}/api/hosts/facts")
    req = Net::HTTP::Post.new(uri.request_uri)
    req.add_field('Accept', 'application/json,version=2')
    req.content_type = 'application/json'
    req.body = body.to_json

    response = connection.request(req)
    unless response.code.start_with?('2')
      raise FactUploadError("#{certname}: During the fact upload the server responded with: #{response.code} #{response.message}. Error is ignored and the execution continues.")
    end

    Cache::INSTANCE.write(cache_name, "Facts from this host were last pushed to #{uri} at #{Time.now}\n")
  rescue FactUploadError
    raise
  rescue StandardError => e
    raise FactUploadError, "Could not send facts to Foreman: #{e}"
  end

  def enc(certname)
    uri = URI.parse("#{base_url}/node/#{certname}?format=yml")
    req = Net::HTTP::Get.new(uri.request_uri)

    response = connection.request(req)
    unless response.code == '200'
      raise NodeRetrievalError, "Error retrieving node #{certname}: #{response.class}\nCheck Foreman's /var/log/foreman/production.log for more information."
    end
    response.body
  end

  private

  def cache_key(certname)
    "#{certname}-push-facts"
  end

  def connection
    @connection ||= initialize_http
  end

  def initialize_http
    uri = URI(base_url)
    res = Net::HTTP.new(uri.host, uri.port)
    res.open_timeout = Settings.timeout
    res.read_timeout = Settings.timeout
    if uri.scheme == 'https'
      res.use_ssl = true
      if (ssl_ca = Settings.ssl_ca)
        res.ca_file = ssl_ca
        res.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
      if (ssl_cert = Settings.ssl_cert) && (ssl_key = Settings.ssl_key)
        res.cert = OpenSSL::X509::Certificate.new(File.read(ssl_cert))
        res.key  = OpenSSL::PKey.new(File.read(ssl_key))
      end
    end
    res
  end

  def build_fact_body(certname, filename)
    puppet_facts = parse_file(filename)
    return if puppet_facts['values'].empty?

    # if there is no environment in facts
    # get it from node file ({Settings.puppet_dir}/yaml/node/
    unless puppet_facts['values'].key?('environment') || puppet_facts['values'].key?('agent_specified_environment')
      node_filename = filename.sub('/facts/', '/node/')
      if File.exist?(node_filename)
        node_data = parse_file(node_filename)

        if node_data.key?('environment')
          puppet_facts['values']['environment'] = node_data['environment']
        end
      end
    end

    begin
      require 'facter'
      puppet_facts['values']['puppetmaster_fqdn'] = Facter.value(:fqdn).to_s
    rescue LoadError
      puppet_facts['values']['puppetmaster_fqdn'] = `hostname -f`.strip
    end

    # filter any non-printable char from the value
    puppet_facts['values'].transform_values! { |val| val.is_a?(String) ? val.scan(/[[:print:]]/).join : val }

    facts = puppet_facts['values']

    {
      'facts' => facts,
      'name' => facts.dig('networking', 'fqdn') || certname,
      'certname' => certname,
    }
  end

  def parse_file(filename)
    case File.extname(filename)
    when '.yaml'
      data = File.read(filename)
      YAML.safe_load(data.gsub(/\!ruby\/object.*$/,''), permitted_classes: [Symbol, Time])
    when '.json'
      JSON.parse(File.read(filename))
    else
      raise "Unknown extension for file '#{filename}'"
    end
  end
end

def enc(certname, strip_environment:)
  Timeout.timeout(Settings.timeout || 10) do
    # send facts to Foreman - enable 'facts' setting to activate
    # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
    client = ForemanClient.new(url)
    client.upload_facts(certname) if Settings.facts?
    result = client.enc(certname)
    if strip_environment
      require 'yaml'
      yaml = YAML.safe_load(result)
      yaml.delete('environment')
      # Always reset the result to back to clean yaml on our end
      result = yaml.to_yaml
    end
    Cache::INSTANCE.write(certname, result)
    result
  end
rescue Timeout::Error, SocketError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, NodeRetrievalError, FactUploadError => e
  warn "Serving cached ENC: #{e}"
  Cache::INSTANCE.read(certname)
end

def push_facts(certname:, threads:, watch:)
  pending = Queue.new

  watchers = threads.times do
    Thread.new do
      client = ForemanClient.new(url)

      while (certname, filename = pending.pop)
        client.upload_facts(certname, filename)
      end
    end
  end

  # TODO: watch and single hostname is inconsistent
  if certname
    pending << [certname, nil]
  else
    Facts.files.each do |filename|
      certname = Facts.certname_from_filename(filename)
      pending << [certname, filename]
    end
  end

  watch_facts(pending) if watch
ensure
  pending&.close
  watchers&.map(&:join)
end

def watch_facts(queue)
  begin
    require 'inotify'
  rescue LoadError
    warn 'You need the `ruby-inotify` (not inotify!) gem to watch for fact updates'
    exit 2
  end

  watch_descriptors = []

  inotify_limit = `sysctl fs.inotify.max_user_watches`.gsub(/[^\d]/, '').to_i

  inotify = Inotify.new

  fact_dir = Facts.directory

  # actually we need only MOVED_TO events because puppet uses File.rename after tmp file created and flushed.
  # see lib/puppet/util.rb near line 469
  inotify.add_watch(fact_dir, Inotify::CREATE | Inotify::MOVED_TO)

  files = Facts.files

  if files.length > inotify_limit
    warn "Looks like your inotify watch limit is #{inotify_limit} but you are asking to watch at least #{files.length} fact files."
    warn 'Increase the watch limit via the system tunable fs.inotify.max_user_watches, exiting.'
    exit 2
  end

  files.each do |f|
    watch_descriptors[inotify.add_watch(f, Inotify::CLOSE_WRITE)] = f
  end

  inotify.each_event do |ev|
    fn = watch_descriptors[ev.wd]
    add_watch = false

    unless fn
      # inotify returns basename for renamed file as ev.name
      # but we need full path
      fn = File.join(fact_dir, ev.name)
      add_watch = true
    end

    next if File.extname(fn) != ".#{Settings.fact_extension}"

    if add_watch || (ev.mask & Inotify::ONESHOT)
      watch_descriptors[inotify.add_watch(fn, Inotify::CLOSE_WRITE)] = fn
    end

    queue << [Facts.certname_from_filename(fn), fn]
  end
end

def run_as_user(username)
  Process::GID.change_privilege(Etc.getgrnam(username).gid) unless Etc.getpwuid.name == username
  Process::UID.change_privilege(Etc.getpwnam(username).uid) unless Etc.getpwuid.name == username
  # Facter (in Settings.threads) tries to read from $HOME, which is still /root after the UID change
  ENV['HOME'] = Etc.getpwnam(username).dir
  # Change CWD to the determined home directory before continuing to make
  # sure we don't reside in /root or anywhere else we don't have access
  # permissions
  Dir.chdir ENV['HOME']
end

# Actual code starts here

if __FILE__ == $0
  # Setuid to puppet user if we can
  begin
    run_as_user(Settings.puppet_user)
  rescue StandardError
    warn "cannot switch to user #{puppet_user}, continuing as '#{Etc.getpwuid.name}'"
  end

  begin
    no_env = ARGV.delete('--no-environment')
    watch = ARGV.delete('--watch-facts')
    push_facts_parallel = ARGV.delete('--push-facts-parallel')
    push_facts = ARGV.delete('--push-facts')
    certname = ARGV[0]

    if push_facts || push_facts_parallel
      # push all facts files to Foreman and don't act as an ENC
      threads = push_facts_parallel ? Settings.threads : 1
      push_facts(certname: certname, threads: threads, watch: watch)
    elsif watch
      raise 'Cannot watch for facts without specifying --push-facts or --push-facts-parallel'
    else
      raise 'Must provide certname as an argument' unless certname

      puts enc(certname, strip_environment: no_env)
    end
  rescue StandardError => e
    warn e
    exit 1
  end
end
