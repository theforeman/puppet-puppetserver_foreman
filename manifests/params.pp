# Defaults for the main class that are fact dependent
# @api private
class puppetserver_foreman::params {
  $lower_fqdn = downcase($facts['networking']['fqdn'])
  $foreman_url = lookup('foreman_proxy::foreman_base_url') |$key| { "https://${lower_fqdn}" }

  if fact('aio_agent_version') =~ String[1] {
    $puppet_basedir = '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/puppet'
    $puppet_etcdir = '/etc/puppetlabs/puppet'
    $puppet_home = '/opt/puppetlabs/server/data/puppetserver'
    $puppet_ssldir = '/etc/puppetlabs/puppet/ssl'
  } else {
    case $facts['os']['family'] {
      'RedHat': {
        $puppet_basedir  = '/usr/share/ruby/vendor_ruby/puppet'
        $puppet_etcdir = '/etc/puppet'
        $puppet_home = '/var/lib/puppet'
      }
      'Debian': {
        $puppet_basedir  = '/usr/lib/ruby/vendor_ruby/puppet'
        $puppet_etcdir = '/etc/puppet'
        $puppet_home = '/var/lib/puppet'
      }
      'Archlinux': {
        # lint:ignore:legacy_facts
        $puppet_basedir = regsubst($facts['rubyversion'], '^(\d+\.\d+).*$', '/usr/lib/ruby/vendor_ruby/\1/puppet')
        # lint:endignore
        $puppet_etcdir = '/etc/puppetlabs/puppet'
        $puppet_home = '/var/lib/puppet'
      }
      /^(FreeBSD|DragonFly)$/: {
        # lint:ignore:legacy_facts
        $puppet_basedir = regsubst($facts['rubyversion'], '^(\d+\.\d+).*$', '/usr/local/lib/ruby/site_ruby/\1/puppet')
        # lint:endignore
        $puppet_etcdir = '/usr/local/etc/puppet'
        $puppet_home = '/var/puppet'
      }
      default: {
        $puppet_basedir = undef
        $puppet_etcdir = undef
        $puppet_home = undef
      }
    }

    $puppet_ssldir = "${puppet_home}/ssl"
  }

  # If CA is specified, remote Foreman host will be verified in reports/ENC scripts
  $client_ssl_ca   = "${puppet_ssldir}/certs/ca.pem"
  # Used to authenticate to Foreman, required if require_ssl_puppetmasters is enabled
  $client_ssl_cert = "${puppet_ssldir}/certs/${lower_fqdn}.pem"
  $client_ssl_key  = "${puppet_ssldir}/private_keys/${lower_fqdn}.pem"

  $enc_fact_extension = bool2str(versioncmp($facts['puppetversion'], '7.0') >= 0, 'json', 'yaml')

  # PE uses a different user/group compared to open source puppet
  # the is_pe fact exists in PE and in stdlib. It can be true/false/undef (undef means open source)
  if $facts['is_pe'] {
    $puppet_user = 'pe-puppet'
    $fact_watcher_service = true
  } else {
    $puppet_user = 'puppet'
    $fact_watcher_service = false
  }
}
