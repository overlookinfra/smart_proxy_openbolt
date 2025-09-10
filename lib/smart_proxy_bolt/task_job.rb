require 'json'
require 'smart_proxy_bolt/error'
require 'smart_proxy_bolt/job'
require 'smart_proxy_bolt/main'
require 'smart_proxy_bolt/result'

module Proxy::Bolt
  class TaskJob < Job
    attr_reader :targets

    # NOTE: Validation of all objects initialized here should be done in
    # main.rb BEFORE creating this object.
    def initialize(name, parameters, options, targets)
      super(name, parameters, options)
      @targets = targets
    end

    def execute
      command = get_cmd
      stdout, stderr, status = Proxy::Bolt.bolt(command)
      result = Proxy::Bolt::Result.new(command, stdout, stderr, status.exitstatus)
    end

    def get_cmd
      # Service config settings (not per-task)
      concurrency = "--concurrency=#{Proxy::Bolt::Plugin.settings.concurrency}"
      connect_timeout = "--connect-timeout=#{Proxy::Bolt::Plugin.settings.connect_timeout}"
      "bolt task run #{@name} --targets #{@targets.join(',')} --no-save-rerun #{concurrency} #{connect_timeout} --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json --no-color #{parse_options} #{parse_parameters}"
    end

    def parse_parameters
      params = []
      @parameters.each do |key, value|
        if value.is_a?(Array)
          params << "#{key}='#{value}'"
        elsif value.is_a?(Hash)
          params << "#{key}='#{value.to_json}'"
        else
          params << "#{key}=#{value}"
        end
      end
      params.join(' ')
    end

    def parse_options
      opt_str = ''
      if @options
        @options.each do |key, value|
          # --noop doesn't have a --[no-] prefix
          next if key == 'noop' && value.is_a?(FalseClass)
          # We expose the --ssl and --ssl-verify options as
          # --winrm-ssl and --winrm-ssl-verify because it's confusing.
          # So strip them out if they're there.
          key = key.sub('winrm-','') if key.start_with?('winrm-')
          # For some mindboggling reason, there are both '--log-level trace'
          # and '--trace' options. We only expose log level, so just
          # tack on --trace if that's what we find.
          if key == 'log-level' && value == 'trace'
            opt_str += "--log-level=trace --trace "
          elsif value.is_a?(TrueClass)
            opt_str += "--#{key} "
          elsif value.is_a?(FalseClass)
            opt_str += "--no-#{key} "
          else
            opt_str += "--#{key}=#{value} "
          end
        end
      end
      opt_str
    end
  end
end
