require 'open3'
require 'smart_proxy_bolt/executor'

module Proxy::Bolt
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self

    # Must be :boolean, :string, or an array of acceptable string values
    VALID_OPTIONS = {
      'noop'             => :boolean,
      'user'             => :string,
      'password'         => :string,
      'private-key'      => :string,
      'host-key-check'   => :boolean,
      'winrm-ssl'        => :boolean,
      'winrm-ssl-verify' => :boolean,
      'run-as'           => :string,
      'sudo-password'    => :string,
      'inventoryfile'    => :string,
      'tmpdir'           => :string,
      'verbose'          => :boolean,
      'trace'            => :boolean,
      'log-level'        => ['error', 'warning', 'info', 'debug', 'trace'],
    }

    VALID_TRANSPORTS = ['ssh', 'winrm']

    def initialize
      @tasks = nil
    end

    def executor
      @executor ||= Proxy::Bolt::Executor.instance
    end

    def tasks(reload: false)
      @tasks = nil if reload
      @tasks || reload_tasks
    end

    def reload_tasks
      @tasks = {}

      # Get a list of all tasks
      command = "bolt task show --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json"
      output, status = bolt(command)
      unless status.exitstatus.zero?
        raise Proxy::Bolt::CliError.new(
          message:  'Error occurred when fetching tasks names.',
          exitcode: status.exitstatus,
          output:   output,
          command:  command,
        )
      end
      task_names = []
      begin
        task_names = JSON.parse(output)['tasks'].map { |t| t[0] }
      rescue JSON::ParserError => e
        raise Proxy::Bolt::Error.new(
          message:   "Error occurred when parsing 'bolt task show' output.",
          exception: e,
        )
      end

      # Get metadata for each task and put into @tasks
      task_names.each do |name|
        command = "bolt task show #{name} --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json"
        output, status = bolt(command)
        unless status.exitstatus.zero?
          @tasks = nil
          raise Proxy::Bolt::CliError.new(
            message:  "Error occurred when fetching task information for #{name}",
            exitcode: status.exitstatus,
            output:   output,
            command:  command,
          )
        end
        metadata = {}
        begin
          metadata = JSON.parse(output)['metadata']
        rescue Json::ParserError => e
          @tasks = nil
          raise Proxy::Bolt::Error.new(
            message:   "Error occurred when parsing 'bolt task show #{name}' output.",
            exception: e,
          )
        end
        if metadata.nil?
          @tasks = nil
          raise Proxy::Bolt::Error.new(
            message: "Invalid metadata found for task #{name}",
            output: output,
            command: command,
          )
        end
        @tasks[name] = {
          'description' => metadata['description'] || '',
          'parameters'  => metadata['parameters'] || {},
        }
      end

      @tasks
    end

    def run_task(data)
      ### Validation ###
      unless data.is_a?(Hash)
        raise Proxy::Bolt::Error.new(message: 'Data passed in to run_task function is not a hash. This is most likely a bug in the smart_proxy_bolt plugin. Please file an issue with the maintainers.').to_json
      end
      fields = ['name', 'parameters', 'targets', 'transport']
      unless fields.all? { |k| data.keys.include?(k) }
        raise Proxy::Bolt::Error.new(message: "You must provide values for 'name', 'parameters', 'targets', and 'transport'.")
      end
      name = data['name']
      params = data['parameters']
      targets = data['targets']
      transport = data['transport']
      options = data['options']

      # Validate name
      raise Proxy::Bolt::Error.new(message: "You must provide a value for 'name'.") unless name.is_a?(String) && !name.empty?
      raise Proxy::Bolt::Error.new(message: "Task #{name} not found.") unless tasks.keys.include?(name)
      
      # Validate parameters
      raise Proxy::Bolt::Error.new(message: "The 'parameters' value should be a hash.") unless params.is_a?(Hash)
      missing = []
      tasks[name]['parameters'].each do |k, v|
        next if v['type'].start_with?('Optional[')
        missing << k unless params.keys.include?(k)
      end
      raise Proxy::Bolt::Error.new(message: "Missing required parameters: #{missing}") unless missing.empty?
      extra = params.keys - tasks[name]['parameters'].keys
      raise Proxy::Bolt::Error.new(message: "Unknown parameters: #{extra}") unless extra.empty?

      # Validate targets
      raise Proxy::Bolt::Error.new(message: "The 'targets' value should be a string or an array.'") unless targets.is_a?(String) || targets.is_a?(Array)
      targets = targets.split(',').map { |t| t.strip }
      raise Proxy::Bolt::Error.new(message: "The 'targets' value should not be empty.") if targets.empty?

      # Validate transport
      raise Proxy::Bolt::Error.new(message: "Invalid transport specified. Must be one of #{VALID_TRANSPORTS}.") unless VALID_TRANSPORTS.include?(transport)
      
      # Validate options
      if options
        raise Proxy::Bolt::Error.new(message: "The 'options' value should be a hash.") unless options.is_a?(Hash)
        unknown = options.keys - VALID_OPTIONS.keys
        raise Proxy::Bolt::Error.new(message: "Invalid options specified: #{unknown}") unless unknown.empty?

        options = options.map do |key, value|
          type = VALID_OPTIONS[key]
          value ||= '' # In case it's nil somehow
          case type
          when :boolean
            value = value.downcase
            raise Proxy::Bolt::Error.new(message: "Option #{key} must be a boolean 'true' or 'false'.") unless ['true', 'false'].include?(value)
            value = value == 'true'
          when :string
            value = value.strip
            raise Proxy::Bolt::Error.new(message: "Option #{key} must have a value when the option is specified.") if value.empty?
          when is_a?(Array)
            value = value.strip
            raise Proxy::Bolt::Error.new(message: "Option #{key} must have one of the following values: #{VALID_OPTIONS[key]}") unless VALID_OPTIONS[key].include?(value)
          end
          [key, value]
        end.to_h
      end

      ### Run the task ###
      task = TaskJob.new(name, params, transport, options, targets)
      id = executor.add_job(task)

      return {
        id: id
      }.to_json
    end

    def get_status(id)
      return {
        status: @executor.status(id),
      }.to_json
    end

    def get_result(id)
      return {
        result: @executor.result(id)
      }.to_json
    end

    def get_error(id)
      e = @executor.error(id)
      if e.is_a?(Proxy::Bolt::Error)
        e = e.to_json
      else
        e = { error: e }.to_json
      end
      e
    end

    def bolt(command)
      env = { 'BOLT_GEM' => 'true', 'BOLT_DISABLE_ANALYTICS' => 'true' }
      Open3.capture2e(env, *command.split)
    end
  end
end
