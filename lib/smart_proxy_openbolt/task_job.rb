require 'json'
require 'smart_proxy_openbolt/error'
require 'smart_proxy_openbolt/job'
require 'smart_proxy_openbolt/result'

module Proxy::OpenBolt
  class TaskJob < Job
    attr_reader :targets

    # NOTE: Validation of all objects initialized here should be done in
    # main.rb BEFORE creating this object.
    def initialize(name, parameters, options, targets)
      super(name, parameters, options)
      @targets = targets
    end

    def execute
      command = ['bolt', 'task', 'run', @name,
                 '--targets', @targets.join(','),
                 '--no-save-rerun',
                 "--concurrency=#{Plugin.settings.concurrency}",
                 "--connect-timeout=#{Plugin.settings.connect_timeout}",
                 '--project', Plugin.settings.environment_path,
                 '--format', 'json',
                 '--no-color']
      command.concat(parse_options)
      command.concat(parse_parameters)
      stdout, stderr, exitcode = Proxy::OpenBolt.openbolt(command)
      Result.new(
        Proxy::OpenBolt.scrub(@options, command.join(' ')),
        Proxy::OpenBolt.scrub(@options, stdout),
        Proxy::OpenBolt.scrub(@options, stderr),
        exitcode
      )
    end

    def parse_parameters
      @parameters.map do |key, value|
        formatted = value.is_a?(Array) || value.is_a?(Hash) ? value.to_json : value
        "#{key}=#{formatted}"
      end
    end

    def parse_options
      opts = []
      return opts unless @options

      @options.each do |key, value|
        # --noop doesn't have a --[no-] prefix
        next if key == 'noop' && value.is_a?(FalseClass)
        # For some mindboggling reason, there are both '--log-level trace'
        # and '--trace' options. We only expose log level, so just
        # tack on --trace if that's what we find.
        if key == 'log-level' && value == 'trace'
          opts << '--log-level=trace'
          opts << '--trace'
        elsif value.is_a?(TrueClass)
          opts << "--#{key}"
        elsif value.is_a?(FalseClass)
          opts << "--no-#{key}"
        else
          opts << "--#{key}=#{value}"
        end
      end
      opts
    end
  end
end
