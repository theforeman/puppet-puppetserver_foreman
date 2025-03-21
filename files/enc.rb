#!/usr/bin/env ruby

# Script usually acts as an ENC for a single host, with the certname supplied as argument
#   if 'facts' is true, the YAML facts for the host are uploaded
#   ENC output is printed and cached
#
# If --push-facts is given as the only arg, it uploads facts for all hosts and then exits.
# Useful in scenarios where the ENC isn't used.

require 'rbconfig'
require 'yaml'

if RbConfig::CONFIG['host_os'] =~ /freebsd|dragonfly/i
  $settings_file ||= '/usr/local/etc/puppet/foreman.yaml'
else
  $settings_file ||= File.exist?('/etc/puppetlabs/puppet/foreman.yaml') ? '/etc/puppetlabs/puppet/foreman.yaml' : '/etc/puppet/foreman.yaml'
end

SETTINGS = YAML.load_file($settings_file)

# Default external encoding
if defined?(Encoding)
  Encoding.default_external = Encoding::UTF_8
end

def url
  SETTINGS[:url] || raise("Must provide URL in #{$settings_file}")
end

def puppetdir
  SETTINGS[:puppetdir] || raise("Must provide puppet base directory in #{$settings_file}")
end

def puppetuser
  SETTINGS[:puppetuser] || 'puppet'
end

def fact_extension
  SETTINGS[:fact_extension] || 'yaml'
end

def fact_directory
  data_dir = fact_extension == 'yaml' ? 'yaml' : 'server_data'
  File.join(puppetdir, data_dir, 'facts')
end

def fact_file(certname)
  File.join(fact_directory, "#{certname}.#{fact_extension}")
end

def fact_files
  Dir[File.join(fact_directory, "*.#{fact_extension}")]
end

def certname_from_filename(filename)
  File.basename(filename, ".#{fact_extension}")
end

def stat_file(certname)
  FileUtils.mkdir_p "#{puppetdir}/yaml/foreman/"
  "#{puppetdir}/yaml/foreman/#{certname}.yaml"
end

def tsecs
  SETTINGS[:timeout] || 10
end

def thread_count
  return SETTINGS[:threads].to_i if not SETTINGS[:threads].nil? and SETTINGS[:threads].to_i > 0
  require 'facter'
  processors = Facter.value(:processorcount).to_i
  processors > 0 ? processors : 1
end

class Http_Fact_Requests
  include Enumerable

  def initialize
    @results_array = []
  end

  def <<(val)
    @results_array << val
  end

  def each(&block)
    @results_array.each(&block)
  end

  def pop
    @results_array.pop
  end
end

class FactUploadError < StandardError; end
class NodeRetrievalError < StandardError; end

require 'etc'
require 'net/http'
require 'net/https'
require 'fileutils'
require 'timeout'
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

def empty_values_hash?(facts_file)
  puppet_facts = parse_file(facts_file)
  puppet_facts['values'].empty?
end

def process_host_facts(certname)
  f = fact_file(certname)
  if File.size(f) != 0
    if empty_values_hash?(f)
      puts "Empty values hash in fact file #{f}, not uploading"
      return 0
    end

    req = generate_fact_request(certname, f)
    begin
      upload_facts(certname, req) if req
      return 0
    rescue => e
      $stderr.puts "During fact upload occurred an exception: #{e}"
      return 1
    end
  else
    $stderr.puts "Fact file #{f} does not contain any facts"
    return 2
  end
end

def process_all_facts(http_requests)
  fact_files.each do |f|
    # Skip empty host fact files
    if File.size(f) != 0
      if empty_values_hash?(f)
        puts "Empty values hash in fact file #{f}, not uploading"
        next
      end

      certname = certname_from_filename(f)
      req = generate_fact_request(certname, f)
      if http_requests
        http_requests << [certname, req]
      elsif req
        upload_facts(certname, req)
      end
    else
      $stderr.puts "Fact file #{f} does not contain any fact"
    end
  end
end

def build_body(certname,filename)
  puppet_facts = parse_file(filename)
  hostname     = puppet_facts['values']['fqdn'] || certname

  # if there is no environment in facts
  # get it from node file ({puppetdir}/yaml/node/
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
    puppet_facts['values']['puppetmaster_fqdn'] = Facter.value('networking.fqdn').to_s
  rescue LoadError
    puppet_facts['values']['puppetmaster_fqdn'] = `hostname -f`.strip
  end

  # filter any non-printable char from the value, if it is a String
  puppet_facts['values'].each do |key, val|
    if val.is_a? String
      puppet_facts['values'][key] = val.scan(/[[:print:]]/).join
    end
  end

  {'facts' => puppet_facts['values'], 'name' => hostname, 'certname' => certname}
end

def initialize_http(uri)
  res              = Net::HTTP.new(uri.host, uri.port)
  res.open_timeout = SETTINGS[:timeout]
  res.read_timeout = SETTINGS[:timeout]
  res.use_ssl      = uri.scheme == 'https'
  if res.use_ssl?
    if SETTINGS[:ssl_ca] && !SETTINGS[:ssl_ca].empty?
      res.ca_file = SETTINGS[:ssl_ca]
      res.verify_mode = OpenSSL::SSL::VERIFY_PEER
    else
      res.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    if SETTINGS[:ssl_cert] && !SETTINGS[:ssl_cert].empty? && SETTINGS[:ssl_key] && !SETTINGS[:ssl_key].empty?
      res.cert = OpenSSL::X509::Certificate.new(File.read(SETTINGS[:ssl_cert]))
      res.key  = OpenSSL::PKey::RSA.new(File.read(SETTINGS[:ssl_key]), nil)
    end
  end
  res
end

def generate_fact_request(certname, filename)
  # Temp file keeping the last run time
  stat = stat_file("#{certname}-push-facts")
  last_run = File.exist?(stat) ? File.stat(stat).mtime.utc : Time.now - 365*24*60*60
  last_fact = File.exist?(filename) ? File.stat(filename).mtime.utc : Time.at(0)
  if last_fact > last_run
    begin
      uri = URI.parse("#{url}/api/hosts/facts")
      req = Net::HTTP::Post.new(uri.request_uri)
      req.add_field('Accept', 'application/json,version=2' )
      req.content_type = 'application/json'
      req.body         = build_body(certname, filename).to_json
      req
    rescue => e
      raise "Could not generate facts for Foreman: #{e}"
    end
  end
end

def cache(certname, result)
  File.open(stat_file(certname), 'w') {|f| f.write(result) }
end

def read_cache(certname)
  File.read(stat_file(certname))
rescue => e
  raise "Unable to read from Cache file: #{e}"
end

def enc(certname)
  uri = URI.parse("#{url}/node/#{certname}?format=yml")
  req = Net::HTTP::Get.new(uri.request_uri)
  initialize_http(uri).start do |http|
    response = http.request(req)

    unless response.code == "200"
      raise NodeRetrievalError, "Error retrieving node #{certname}: #{response.class}\nCheck Foreman's /var/log/foreman/production.log for more information."
    end
    response.body
  end
end

def upload_facts(certname, req)
  return nil if req.nil?
  uri = URI.parse("#{url}/api/hosts/facts")
  begin
    initialize_http(uri).start do |http|
      response = http.request(req)
      if response.code.start_with?('2')
        cache("#{certname}-push-facts", "Facts from this host were last pushed to #{uri} at #{Time.now}\n")
      else
        $stderr.puts "#{certname}: During the fact upload the server responded with: #{response.code} #{response.message}. Error is ignored and the execution continues."
        $stderr.puts response.body
      end
    end
  rescue => e
    $stderr.puts "During fact upload occured an exception: #{e}"
    raise FactUploadError, "Could not send facts to Foreman: #{e}"
  end
end

def upload_facts_parallel(http_fact_requests, wait = true)
  t = thread_count.times.map {
    Thread.new(http_fact_requests) do |fact_requests|
    while factref = fact_requests.pop
      certname         = factref[0]
      httpobj          = factref[1]
      if httpobj
        upload_facts(certname, httpobj)
      end
    end
    end
  }
  if wait
    t.each(&:join)
  end
end

def watch_and_send_facts(parallel)
  begin
    require 'inotify'
  rescue LoadError
    puts "You need the `ruby-inotify` (not inotify!) gem to watch for fact updates"
    exit 2
  end

  watch_descriptors = []
  pending = []
  threads = thread_count
  last_send = Time.now

  inotify_limit = `sysctl fs.inotify.max_user_watches`.gsub(/[^\d]/, '').to_i

  inotify = Inotify.new

  fact_dir = fact_directory

  # actually we need only MOVED_TO events because puppet uses File.rename after tmp file created and flushed.
  # see lib/puppet/util.rb near line 469
  inotify.add_watch(fact_dir, Inotify::CREATE | Inotify::MOVED_TO )

  files = fact_files

  if files.length > inotify_limit
    puts "Looks like your inotify watch limit is #{inotify_limit} but you are asking to watch at least #{files.length} fact files."
    puts "Increase the watch limit via the system tunable fs.inotify.max_user_watches, exiting."
    exit 2
  end

  files.each do |f|
    begin
      watch_descriptors[inotify.add_watch(f, Inotify::CLOSE_WRITE)] = f
    end
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

    if File.extname(fn) != ".#{fact_extension}"
      next
    end

    if add_watch || (ev.mask & Inotify::ONESHOT)
      watch_descriptors[inotify.add_watch(fn, Inotify::CLOSE_WRITE)] = fn
    end

    if fn
      certname = certname_from_filename(fn)
      req = generate_fact_request certname, fn
      if parallel
        pending << [certname,req]
      else
        upload_facts(certname,req)
      end
    end
    if parallel && (pending.length >= threads || ((last_send + 5) < Time.now))
      if pending.length > 0
        upload_facts_parallel(pending, false)
        pending = []
      end
      last_send = Time.now
    end
  end
end

# Actual code starts here

if __FILE__ == $0 then
  # Setuid to puppet user if we can
  begin
    Process::GID.change_privilege(Etc.getgrnam(puppetuser).gid) unless Etc.getpwuid.name == puppetuser
    Process::UID.change_privilege(Etc.getpwnam(puppetuser).uid) unless Etc.getpwuid.name == puppetuser
    # Facter (in thread_count) tries to read from $HOME, which is still /root after the UID change
    ENV['HOME'] = Etc.getpwnam(puppetuser).dir
    # Change CWD to the determined home directory before continuing to make
    # sure we don't reside in /root or anywhere else we don't have access
    # permissions
    Dir.chdir ENV['HOME']
  rescue
    $stderr.puts "cannot switch to user #{puppetuser}, continuing as '#{Etc.getpwuid.name}'"
  end

  begin
    no_env = ARGV.delete("--no-environment")
    watch = ARGV.delete("--watch-facts")
    push_facts_parallel = ARGV.delete("--push-facts-parallel")
    push_facts = ARGV.delete("--push-facts")
    if watch && ! ( push_facts || push_facts_parallel )
        raise "Cannot watch for facts without specifying --push-facts or --push-facts-parallel"
    end
    if push_facts
      # push all facts files to Foreman and don't act as an ENC
      if ARGV.empty?
        process_all_facts(false)
      else
        process_host_facts(ARGV[0])
      end
    elsif push_facts_parallel
      http_fact_requests = Http_Fact_Requests.new
      process_all_facts(http_fact_requests)
      upload_facts_parallel(http_fact_requests)
    else
      certname = ARGV[0] || raise("Must provide certname as an argument")
      #
      # query External node
      begin
        result = ""
        Timeout.timeout(tsecs) do
          # send facts to Foreman - enable 'facts' setting to activate
          # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
          #
          if SETTINGS[:facts]
            req = generate_fact_request(certname, fact_file(certname))
            upload_facts(certname, req)
          end

          result = enc(certname)
          cache(certname, result)
        end
      rescue Timeout::Error, SocketError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, NodeRetrievalError, FactUploadError => e
        $stderr.puts "Serving cached ENC: #{e}"
        # Read from cache, we got some sort of an error.
        result = read_cache(certname)
      end

      if no_env
        require 'yaml'
        yaml = YAML.safe_load(result)
        yaml.delete('environment')
        # Always reset the result to back to clean yaml on our end
        puts yaml.to_yaml
      else
        puts result
      end
    end
  rescue => e
    warn e
    exit 1
  end
  if watch
    watch_and_send_facts(push_facts_parallel)
  end
end
