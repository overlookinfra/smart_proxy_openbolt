require 'smart_proxy_bolt/job'
require 'smart_proxy_bolt/error'
require 'smart_proxy_bolt/bolt_main'
require 'smart_proxy_bolt/result'
require 'json'

module Proxy::Bolt
  class TaskJob < Job
    attr_reader :targets

    # NOTE: Validation of all objects initialized here should be done in
    # bolt_main.rb BEFORE creating this object.
    def initialize(name, parameters, transport, options, targets)
      super(name, parameters, transport, options)
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
      "bolt task run #{@name} --targets #{@targets.join(',')} --transport #{@transport} --no-save-rerun #{concurrency} #{connect_timeout} --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json --no-color #{parse_options} #{parse_parameters}"
    end

    def parse_parameters
      params = ''
      @parameters.each do |key, value|
        if value.is_a?(Array)
          params += "#{key}='#{value}' "
        elsif value.is_a?(Hash)
          params += "#{key}='#{value.to_json}' "
        else
          "#{key}=#{value}"
        end
      end
      params
    end

    def parse_options
      opt_str = ''
      if @options
        @options.each do |key, value|
          if value.is_a?(TrueClass)
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
