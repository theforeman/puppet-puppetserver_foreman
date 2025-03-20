# @summary Set up Foreman integration for a Puppetserver
#
# This class includes the necessary scripts for Foreman on the puppetmaster and
# is intented to be added to your puppetmaster
#
# @param foreman_url
#   The Foreman URL
# @param ssl_ca
#   The SSL CA file path to use
# @param ssl_cert
#   The SSL certificate file path to use
# @param ssl_key
#   The SSL key file path to use
# @param puppet_etcdir
#   The directory used to put the configuration in.
# @param puppet_user
#   The user used to run the Puppetserver
# @param puppet_group
#   The group used to run the Puppetserver
#
# @param enc
#   Whether to install the ENC script
# @param enc_timeout
#   The timeout to use on HTTP calls in the ENC script
# @param enc_upload_facts
#   Whether to configure the ENC to send facts to Foreman
# @param puppet_home
#   The Puppet home where the YAML files with facts live. Used for the ENC script
# @param enc_fact_extension
#   The fact extension to use. Support for json was added in Puppetserver
#   6.20.0. Puppetserver < 7 defaults to yaml, >= 7 defaults to json.
#
# @param reports
#   Whether to enable the report processor
# @param reports_timeout
#   The timeout to use on HTTP calls in the report processor
# @param report_retry_limit
#   The number of times to retry HTTP calls in the report processor
# @param puppet_basedir
#   The directory used to install the report processor to
# @param use_client_tls_certs
#   Enable client TLS authentication to foreman
# @param fact_watcher_service
#   Sets up a simple systemd unit that watches for new fact files and publishes them to foreman. Not required when foreman is the ENC
# @param manage_fact_watcher_dependencies
#   Install the missing dependencies for fact_watchter
class puppetserver_foreman (
  Stdlib::HTTPUrl $foreman_url = $puppetserver_foreman::params::foreman_url,
  Boolean $enc = true,
  Integer[0] $enc_timeout = 60,
  Boolean $enc_upload_facts = true,
  Enum['yaml', 'json'] $enc_fact_extension = $puppetserver_foreman::params::enc_fact_extension,
  Stdlib::Absolutepath $puppet_home = $puppetserver_foreman::params::puppet_home,
  String $puppet_user = $puppetserver_foreman::params::puppet_user,
  String $puppet_group = $puppet_user,
  Stdlib::Absolutepath $puppet_basedir = $puppetserver_foreman::params::puppet_basedir,
  Stdlib::Absolutepath $puppet_etcdir = $puppetserver_foreman::params::puppet_etcdir,
  Boolean $reports = true,
  Integer[0] $reports_timeout = 60,
  Integer[0] $report_retry_limit = 1,
  Variant[Enum[''], Stdlib::Absolutepath] $ssl_ca = $puppetserver_foreman::params::client_ssl_ca,
  Variant[Enum[''], Stdlib::Absolutepath] $ssl_cert = $puppetserver_foreman::params::client_ssl_cert,
  Variant[Enum[''], Stdlib::Absolutepath] $ssl_key = $puppetserver_foreman::params::client_ssl_key,
  Boolean $use_client_tls_certs = true,
  Boolean $fact_watcher_service = $puppetserver_foreman::params::fact_watcher_service,
  Boolean $manage_fact_watcher_dependencies = true,
) inherits puppetserver_foreman::params {
  case $facts['os']['family'] {
    'Debian': { $json_package = 'ruby-json' }
    default:  { $json_package = 'rubygem-json' }
  }

  stdlib::ensure_packages([$json_package])

  file { "${puppet_etcdir}/foreman.yaml":
    content => template("${module_name}/puppet.yaml.erb"),
    mode    => '0640',
    owner   => 'root',
    group   => $puppet_group,
  }

  if $reports {
    exec { 'Create Puppet Reports dir':
      command => "/bin/mkdir -p ${puppet_basedir}/reports",
      creates => "${puppet_basedir}/reports",
    }

    file { "${puppet_basedir}/reports/foreman.rb":
      ensure  => file,
      content => file("${module_name}/report.rb"),
      mode    => '0644',
      owner   => 'root',
      group   => '0',
      require => Exec['Create Puppet Reports dir'],
    }
  }

  if $enc {
    file { "${puppet_etcdir}/node.rb":
      ensure  => file,
      content => file("${module_name}/enc.rb"),
      mode    => '0550',
      owner   => $puppet_user,
      group   => $puppet_group,
    }

    file { "${puppet_home}/yaml":
      ensure                  => directory,
      owner                   => $puppet_user,
      group                   => $puppet_group,
      mode                    => '0750',
      selinux_ignore_defaults => true,
    }

    file { "${puppet_home}/yaml/foreman":
      ensure => directory,
      owner  => $puppet_user,
      group  => $puppet_group,
      mode   => '0750',
    }

    file { "${puppet_home}/yaml/node":
      ensure => directory,
      owner  => $puppet_user,
      group  => $puppet_group,
      mode   => '0750',
    }

    file { "${puppet_home}/yaml/facts":
      ensure => directory,
      owner  => $puppet_user,
      group  => $puppet_group,
      mode   => '0750',
    }
    if $manage_fact_watcher_dependencies {
      $ensure = if $fact_watcher_service {
        'installed'
      } else {
        'absent'
      }
      package { 'ruby-inotify':
        ensure   => 'installed',
        provider => 'puppet_gem',
        before   => Systemd::Unit_file['fact_watcher.service'],
      }
    }
    systemd::manage_unit { 'fact_watcher.service':
      enable        => $fact_watcher_service,
      active        => $fact_watcher_service,
      unit_entry    => {
        'Description' => 'Publish facts to Foreman',
      },
      service_entry => {
        'Type'        => 'simple',
        'Environment' => "PATH=/opt/puppetlabs/puppet/bin:${facts['path']}",
        'User'        => $puppet_user,
        'ExecStart'   => "${puppet_etcdir}/node.rb --watch-facts --push-facts-parallel",
      },
      install_entry => {
        'WantedBy' => 'multi-user.target',
      },
    }
  }
}
