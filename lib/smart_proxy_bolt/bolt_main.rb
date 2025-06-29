require 'open3'
require 'smart_proxy_bolt/executor'
require 'smart_proxy_bolt/error'

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
    @@mutex = Mutex.new

    def executor
      @executor ||= Proxy::Bolt::Executor.instance
    end

    # /tasks or /tasks/reload
    def tasks(reload: false)
      # If we need to reload, only one instance of the reload
      # should happen at once. Make others wait until it is
      # finished.
      @@mutex.synchronize do
        @tasks = nil if reload
        @tasks || reload_tasks
      end
    end

    def reload_tasks
      # DEBUG: Remove this
      @tasks = JSON.parse(File.read('/tasks'))
      return
      task_data = {}

      # Get a list of all tasks
      command = "bolt task show --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json"
      stdout, stderr, status = bolt(command)
      unless status.exitstatus.zero?
        raise Proxy::Bolt::CliError.new(
          message:  'Error occurred when fetching tasks names.',
          exitcode: status.exitstatus,
          stdout:   stdout,
          stderr:   stderr,
          command:  command,
        )
      end
      task_names = []
      begin
        task_names = JSON.parse(stdout)['tasks'].map { |t| t[0] }
      rescue JSON::ParserError => e
        raise Proxy::Bolt::Error.new(
          message:   "Error occurred when parsing 'bolt task show' output.",
          exception: e,
        )
      end

      # Get metadata for each task and put into @tasks
      task_names.each do |name|
        command = "bolt task show #{name} --project #{Proxy::Bolt::Plugin.settings.environment_path} --format json"
        stdout, stderr, status = bolt(command)
        unless status.exitstatus.zero?
          @tasks = nil
          raise Proxy::Bolt::CliError.new(
            message:  "Error occurred when fetching task information for #{name}",
            exitcode: status.exitstatus,
            stdout:   stdout,
            stderr:   stderr,
            command:  command,
          )
        end
        metadata = {}
        begin
          metadata = JSON.parse(stdout)['metadata']
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
        task_data[name] = {
          'description' => metadata['description'] || '',
          'parameters'  => metadata['parameters'] || {},
        }
      end
      @tasks = task_data
    end

    # /run/task
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
      
      options ||= {}
      # Validate options
      raise Proxy::Bolt::Error.new(message: "The 'options' value should be a hash.") unless options.is_a?(Hash)
      # Inject the log-level param if it doesn't exist so we always get something
      # for the log file.
      options['log-level'] ||= 'debug'
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

      ### Run the task ###
      task = TaskJob.new(name, params, transport, options, targets)
      id = executor.add_job(task)

      return {
        id: id
      }.to_json
    end

    # /job/:id/status
    def get_status(id)
      return {
        status: executor.status(id),
      }.to_json
    end

    # /job/:id/result
    def get_result(id)
      executor.result(id).to_json
    end

    # Anything that needs to run a Bolt CLI command should use this.
    # At the moment, the full output is held in memory and passed back.
    # If this becomes a problem, we can stream to disk and point to it.
    #
    # For task runs, the log goes to stderr and the result to stdout when
    # --format json is specified. At some point, figure out how to make
    # Bolt's logger log to a file instead without having to have a special
    # project config file.
    def bolt(command)
      env = { 'BOLT_GEM' => 'true', 'BOLT_DISABLE_ANALYTICS' => 'true' }
      Open3.capture3(env, *command.split)
    end
  end
end
