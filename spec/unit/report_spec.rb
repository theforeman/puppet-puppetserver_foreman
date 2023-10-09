require 'spec_helper'
require 'yaml'
require 'tempfile'

describe 'foreman_report_processor' do
  settings = Tempfile.new('foreman.yaml')
  settings.write(<<-EOF)
---
:url: "http://localhost:3000"
:facts: true
:puppet_home: "/var/lib/puppet"
:report_retry_limit: 2
  EOF
  settings.close
  $settings_file = settings.path
  eval File.read(File.join(__dir__, '..', '..', 'files', 'report.rb'))
  let(:processor) { Puppet::Reports.report(:foreman) }

  subject do
    path = File.join(static_fixture_path, report)
    content = if YAML.respond_to?(:safe_load_file)
                YAML.safe_load_file(
                  path,
                  aliases: true,
                  permitted_classes: [Symbol, Time, Puppet::Util::Log, Puppet::Transaction::Report, Puppet::Resource::Status, Puppet::Transaction::Event, Puppet::Util::Metric]
                )
              else
                YAML.load_file(path)
              end
    content.extend(processor)
  end

  describe "making a connection" do
    let(:report) { 'report-format-3.yaml' }

    it "should connect to the URL in the processor" do
      stub = stub_request(:post, "http://localhost:3000/api/config_reports")
      subject.process
      expect(stub).to have_been_requested
    end
  end

  describe "retry on failed connection" do
    let(:report) { 'report-format-3.yaml' }

    it "should retry the URL in the processor" do
      stub = stub_request(:post, "http://localhost:3000/api/config_reports").to_timeout().then().to_return({status: [200, 'OK']})
      expect { subject.process }.not_to raise_error
      expect(stub).to have_been_requested.times(2)
    end

    it "should give up after the configured retries" do
      stub = stub_request(:post, "http://localhost:3000/api/config_reports").to_timeout()
      expect { subject.process }.to raise_error(Puppet::Error, /Could not send report to Foreman at/)
      expect(stub).to have_been_requested.times(2)
    end
  end

  describe "Puppet Report Format 2" do
    let(:report) { 'report-format-2.yaml' }

    it {
      expect(subject.generate_report).to eql(JSON.parse(File.read("#{static_fixture_path}/report-format-2.json")))
    }
  end

  describe "Puppet Report Format 3" do
    let(:report) { 'report-format-3.yaml' }

    it {
      expect(subject.generate_report).to eql(JSON.parse(File.read("#{static_fixture_path}/report-format-3.json")))
    }
  end

  describe "Puppet Report Format 6" do
    let(:report) { 'report-format-6.yaml' }

    it {
      expect(subject.generate_report).to eql(JSON.parse(File.read("#{static_fixture_path}/report-format-6.json")))
    }
  end

  describe "report should support failure metrics" do
    let(:report) { 'report-2.6.5-errors.yaml' }

    it {
      expect(subject.generate_report['status']['failed']).to eql 3
    }
  end

  describe "report should not support noops" do
    let(:report) { 'report-2.6.12-noops.yaml' }

    it {
      expect(subject.generate_report['status']['pending']).to eql 10
    }
  end

  describe "empty reports have the correct format" do
    let(:report) { 'report-empty.yaml' }

    it {
      expect(subject.generate_report).to eql(JSON.parse(File.read("#{static_fixture_path}/report-empty.json")))
    }
  end

  describe "report should not include finished_catalog_run messages" do
    let(:report) { 'report-2.6.12-noops.yaml' }

    it {
      expect(subject.generate_report['logs'].map { |l| l['log']['messages']['message']}.to_s).not_to match(/Finished catalog run in/)
    }
  end

  describe "report should not include debug level messages" do
    let(:report) { 'report-2.6.2-debug.yaml' }

    it {
      expect(subject.generate_report['logs'].map { |l| l['log']['level']}.to_s).not_to match(/debug/)
    }
  end

  describe "report should show failure metrics for failed catalog fetches" do
    let(:report) { 'report-3.5.1-catalog-errors.yaml' }

    it {
      expect(subject.generate_report['status']['failed']).to eql 1
    }
  end

  describe "report should properly bypass log processor changes" do
    let(:report) { 'report-log-preprocessed.yaml' }

    it {
      expect(subject.generate_report['status']['failed']).to eql 1
    }
  end

  # TODO: check debug logs are filtered

  # Normally we wouldn't include commented code, but this is a handy way
  # of seeing what the report processor generates for a given YAML input
  #
  #describe "foo" do
  #  subject { YAML.load_file("#{yamldir}/report-format-1.yaml").extend(processor) }
  #  it { puts JSON.pretty_generate(subject.generate_report) }
  #end

end
