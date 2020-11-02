require 'spec_helper'

describe 'puppetserver_foreman' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { override_facts(os_facts, {networking: {fqdn: 'foreman.example.com'}}) }
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

      describe 'without custom parameters' do
        it { should contain_class('puppetserver_foreman::params') }

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
          should contain_package(json_package).with_ensure('present')
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
            ':timeout: 60',
            ':report_timeout: 60',
            ':threads: null',
          ])
        end
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
    end
  end
end