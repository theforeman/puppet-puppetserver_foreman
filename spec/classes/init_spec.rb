require 'spec_helper'

describe 'puppetserver_foreman' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { override_facts(os_facts, networking: {fqdn: 'foreman.example.com'}) }
      let(:site_ruby) do
        short_ruby_version = facts[:rubyversion].split('.')[0..1].join('.')
        case facts[:os]['family']
        when 'Archlinux'
          "/usr/lib/ruby/vendor_ruby/#{short_ruby_version}"
        when 'DragonFly', 'FreeBSD'
          "/usr/local/lib/ruby/site_ruby/#{short_ruby_version}"
        else
          '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby'
        end
      end

      let(:etc_dir) do
        case facts[:os]['family']
        when 'DragonFly', 'FreeBSD'
          '/usr/local/etc/puppet'
        else
          '/etc/puppetlabs/puppet'
        end
      end

      let(:var_dir) do
        case facts[:os]['family']
        when 'Archlinux'
          '/var/lib/puppet'
        when 'DragonFly', 'FreeBSD'
          '/var/puppet'
        else
          '/opt/puppetlabs/server/data/puppetserver'
        end
      end

      let(:ssl_dir) do
        case facts[:os]['family']
        when 'Archlinux', 'DragonFly', 'FreeBSD'
          "#{var_dir}/ssl"
        else
          "#{etc_dir}/ssl"
        end
      end

      let(:json_package) { facts[:os]['family'] == 'Debian' ? 'ruby-json' : 'rubygem-json' }

      let(:fact_extension) { facts[:puppetversion].to_i >= 7 ? 'json' : 'yaml' }

      describe 'without custom parameters' do
        it { should contain_class('puppetserver_foreman::params') }
        it do
          should contain_class('puppetserver_foreman')
            .with_enc_fact_extension(fact_extension)
            .with_puppet_home(var_dir)
            .with_puppet_basedir("#{site_ruby}/puppet")
            .with_puppet_etcdir(etc_dir)
            .with_ssl_ca(%r{^#{ssl_dir}/.+\.pem$})
            .with_ssl_cert(%r{^#{ssl_dir}/.+\.pem$})
            .with_ssl_key(%r{^#{ssl_dir}/.+\.pem$})
        end

        it 'should set up reports' do
          should contain_exec('Create Puppet Reports dir')
            .with_command("/bin/mkdir -p #{site_ruby}/puppet/reports")
            .with_creates("#{site_ruby}/puppet/reports")

          should contain_file("#{site_ruby}/puppet/reports/foreman.rb")
            .with_mode('0644')
            .with_owner('root')
            .with_group('0')
            .with_content(%r{foreman\.yaml})
            .with_require('Exec[Create Puppet Reports dir]')
        end

        it 'should set up enc' do
          should contain_file("#{etc_dir}/node.rb")
            .with_mode('0550')
            .with_owner('puppet')
            .with_group('puppet')
            .with_content(%r{foreman\.yaml})

          should_not contain_systemd__unit_file('facts.service')
        end

        it 'should set up directories for the ENC' do
          should contain_file("#{var_dir}/yaml")
            .with_ensure('directory')
            .with_owner('puppet')
            .with_group('puppet')
            .with_mode('0750')
          should contain_file("#{var_dir}/yaml/facts")
            .with_ensure('directory')
            .with_owner('puppet')
            .with_group('puppet')
            .with_mode('0750')
          should contain_file("#{var_dir}/yaml/foreman")
            .with_ensure('directory')
            .with_owner('puppet')
            .with_group('puppet')
            .with_mode('0750')
          should contain_file("#{var_dir}/yaml/node")
            .with_ensure('directory')
            .with_owner('puppet')
            .with_group('puppet')
            .with_mode('0750')
        end

        it 'should install json package' do
          should contain_package(json_package).with_ensure('installed')
        end

        it 'should create puppet.yaml' do
          should contain_file("#{etc_dir}/foreman.yaml")
            .with_mode('0640')
            .with_owner('root')
            .with_group('puppet')

          verify_exact_contents(catalogue, "#{etc_dir}/foreman.yaml", [
            "---",
            ':url: "https://foreman.example.com"',
            ":ssl_ca: \"#{ssl_dir}/certs/ca.pem\"",
            ":ssl_cert: \"#{ssl_dir}/certs/foreman.example.com.pem\"",
            ":ssl_key: \"#{ssl_dir}/private_keys/foreman.example.com.pem\"",
            ":puppetdir: \"#{var_dir}\"",
            ':puppetuser: "puppet"',
            ':facts: true',
            ":fact_extension: \"#{fact_extension}\"",
            ':timeout: 60',
            ':report_timeout: 60',
            ':report_retry_limit: 1',
            ':threads: null',
          ])
        end
      end

      describe 'without TLS client authenticatio' do
        let :params do
          { use_client_tls_certs: false }
        end

        it { is_expected.to contain_file("#{etc_dir}/foreman.yaml").without_content(%r{:ssl_(cert|key):}) }
      end

      describe 'without reports' do
        let :params do
          { reports: false }
        end

        it 'should not include reports' do
          should_not contain_exec('Create Puppet Reports dir')
          should_not contain_file("#{site_ruby}/puppet/reports/foreman.rb")
        end
      end

      describe 'without enc' do
        let :params do
          { enc: false }
        end

        it 'should not include enc' do
          should_not contain_file("#{etc_dir}/node.rb")
        end
      end

      describe 'with foreman_url via Hiera' do
        let(:hiera_config) { 'spec/fixtures/hiera/hiera.yaml' }

        it { should contain_class('puppetserver_foreman').with_foreman_url('https://hiera-foreman.example.com') }
      end
      describe 'setup service to pubish facts' do
        let :params do
          {fact_watcher_service: true}
        end
        it { is_expected.to contain_systemd__unit_file('fact_watcher.service') }
      end
    end
  end
end
