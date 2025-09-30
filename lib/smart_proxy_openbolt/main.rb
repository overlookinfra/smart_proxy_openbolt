require 'json'
require 'open3'
require 'smart_proxy_openbolt/executor'
require 'smart_proxy_openbolt/error'
require 'thread'

module Proxy::OpenBolt
  extend ::Proxy::Util
  extend ::Proxy::Log

  TRANSPORTS = ['ssh', 'winrm']
  # The key should be exactly the flag name passed to OpenBolt
  # Type must be :boolean, :string, or an array of acceptable string values
  # Transport must be an array of transport types it applies to. This is
  #   used to filter the openbolt options in the UI to only those relevant
  # Defaults set here are in case the UI does not send any information for
  #   the key, and should only be present if this value is required
  # Sensitive should be set to true in order to redact the value from logs
  OPENBOLT_OPTIONS = {
    'transport' => {
      :type => TRANSPORTS,
      :transport => TRANSPORTS,
      :default => 'ssh',
      :sensitive => false,
      :description => 'The transport method to use for connecting to target hosts.',
    },
    'log-level' => {
      :type => ['error', 'warning', 'info', 'debug', 'trace'],
      :transport => ['ssh', 'winrm'],
      :sensitive => false,
      :description => 'Set the log level during OpenBolt execution.',
    },
    'verbose' => {
      :type => :boolean,
      :transport => ['ssh', 'winrm'],
      :sensitive => false,
      :description => 'Run the OpenBolt command with the --verbose flag. This prints additional information during OpenBolt execution and will print any out::verbose plan statements.',
    },
    'noop' => {
      :type => :boolean,
      :transport => ['ssh', 'winrm'],
      :sensitive => false,
      :description => 'Run the OpenBolt command with the --noop flag, which will make no changes to the target host.',
    },
    'tmpdir' => {
      :type => :string,
      :transport => ['ssh', 'winrm'],
      :sensitive => false,
      :description => 'Directory to use for temporary files on target hosts during OpenBolt execution.',
    },
    'user' => {
      :type => :string,
      :transport => ['ssh', 'winrm'],
      :sensitive => false,
      :description => 'Username used for SSH or WinRM authentication.',
    },
    'password' => {
      :type => :string,
      :transport => ['ssh', 'winrm'],
      :sensitive => true,
      :description => 'Password used for SSH or WinRM authentication.',
    },
    'host-key-check' => {
      :type => :boolean,
      :transport => ['ssh'],
      :sensitive => false,
      :description => 'Whether to perform host key verification when connecting to targets over SSH.',
    },
    'private-key' => {
      :type => :string,
      :transport => ['ssh'],
      :sensitive => false,
      :description => 'Path on the smart proxy host to the private key used for SSH authentication. This key must be readable by the foreman-proxy user.',
    },
    'run-as' => {
      :type => :string,
      :transport => ['ssh'],
      :sensitive => false,
      :description => 'The user to run commands as on the target host. This requires that the user specified in the "user" option has permission to run commands as this user.',
    },
    'sudo-password' => {
      :type => :string,
      :transport => ['ssh'],
      :sensitive => true,
      :description => 'Password used for privilege escalation when using SSH.',
    },
    'ssl' => {
      :type => :boolean,
      :transport => ['winrm'],
      :sensitive => false,
      :description => 'Use SSL when connecting to hosts via WinRM.',
    },
    'ssl-verify' => {
      :type => :boolean,
      :transport => ['winrm'],
      :sensitive => false,
      :description => 'Verify remote host SSL certificate when connecting to hosts via WinRM.',
    },
  }
  class << self
    @@mutex = Mutex.new

    def openbolt_options
      OPENBOLT_OPTIONS.sort.to_h
    end

    def executor
      @executor ||= Proxy::OpenBolt::Executor.instance
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
      task_data = {}

      # Get a list of all tasks
      command = "bolt task show --project #{Proxy::OpenBolt::Plugin.settings.environment_path} --format json"
      stdout, stderr, status = openbolt(command)
      unless status.exitstatus.zero?
        raise Proxy::OpenBolt::CliError.new(
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
        raise Proxy::OpenBolt::Error.new(
          message:   "Error occurred when parsing 'bolt task show' output.",
          exception: e,
        )
      end

      # Get metadata for each task and put into @tasks
      task_names.each do |name|
        command = "bolt task show #{name} --project #{Proxy::OpenBolt::Plugin.settings.environment_path} --format json"
        stdout, stderr, status = openbolt(command)
        unless status.exitstatus.zero?
          @tasks = nil
          raise Proxy::OpenBolt::CliError.new(
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
          raise Proxy::OpenBolt::Error.new(
            message:   "Error occurred when parsing 'bolt task show #{name}' output.",
            exception: e,
          )
        end
        if metadata.nil?
          @tasks = nil
          raise Proxy::OpenBolt::Error.new(
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

    # Normalize options and parameters, since the UI may send unspecified options as empty strings
    def normalize_values(hash)
      return {} unless hash.is_a?(Hash)
      hash.transform_values do |value|
        if value.is_a?(String)
          value = value.strip
          value = nil if value.empty?
        elsif value.is_a?(Array)
          value = value.map { |v| v.is_a?(String) ? v.strip : v }
          value = nil if value.empty?
        end
        value
      end.compact
    end

    # /launch/task
    def launch_task(data)
      ### Validation ###
      unless data.is_a?(Hash)
        raise Proxy::OpenBolt::Error.new(message: 'Data passed in to launch_task function is not a hash. This is most likely a bug in the smart_proxy_openbolt plugin. Please file an issue with the maintainers.').to_json
      end
      fields = ['name', 'parameters', 'targets', 'options']
      unless fields.all? { |k| data.keys.include?(k) }
        raise Proxy::OpenBolt::Error.new(message: "You must provide values for 'name', 'parameters', 'targets', and 'transport'.")
      end
      name = data['name']
      params = data['parameters'] || {}
      targets = data['targets']
      options = data['options']

      logger.info("Task: #{name}")
      logger.info("Parameters: #{params.inspect}")
      logger.info("Targets: #{targets.inspect}")
      logger.info("Options: #{scrub(options, options.inspect.to_s)}")

      # Validate name
      raise Proxy::OpenBolt::Error.new(message: "You must provide a value for 'name'.") unless name.is_a?(String) && !name.empty?
      raise Proxy::OpenBolt::Error.new(message: "Task #{name} not found.") unless tasks.keys.include?(name)

      # Validate parameters
      raise Proxy::OpenBolt::Error.new(message: "The 'parameters' value should be a hash.") unless params.is_a?(Hash)
      missing = []
      tasks[name]['parameters'].each do |k, v|
        next if v['type'].start_with?('Optional[')
        missing << k unless params.keys.include?(k)
      end
      raise Proxy::OpenBolt::Error.new(message: "Missing required parameters: #{missing}") unless missing.empty?
      extra = params.keys - tasks[name]['parameters'].keys
      raise Proxy::OpenBolt::Error.new(message: "Unknown parameters: #{extra}") unless extra.empty?

      # Normalize parameters, ensuring blank values are not passed
      params = normalize_values(params)
      logger.info("Normalized parameters: #{params.inspect}")

      # Validate targets
      raise Proxy::OpenBolt::Error.new(message: "The 'targets' value should be a string or an array.'") unless targets.is_a?(String) || targets.is_a?(Array)
      targets = targets.split(',').map { |t| t.strip }
      raise Proxy::OpenBolt::Error.new(message: "The 'targets' value should not be empty.") if targets.empty?

      options ||= {}
      # Validate options
      raise Proxy::OpenBolt::Error.new(message: "The 'options' value should be a hash.") unless options.is_a?(Hash)
      extra = options.keys - OPENBOLT_OPTIONS.keys
      raise Proxy::OpenBolt::Error.new(message: "Invalid options specified: #{extra}") unless extra.empty?
      unknown = options.keys - OPENBOLT_OPTIONS.keys
      raise Proxy::OpenBolt::Error.new(message: "Invalid options specified: #{unknown}") unless unknown.empty?

      # Normalize options, removing blank values
      options = normalize_values(options)
      logger.info("Normalized options: #{scrub(options, options.inspect.to_s)}")
      OPENBOLT_OPTIONS.each { |key, value| options[key] ||= value[:default] if value.key?(:default) }
      logger.info("Options with required defaults: #{scrub(options, options.inspect.to_s)}")

      # Validate option types
      options = options.map do |key, value|
        type = OPENBOLT_OPTIONS[key][:type]
        value = value.nil? ? '' : value # Just in case
        case type
        when :boolean
          if value.is_a?(String)
            value = value.downcase.strip
            raise Proxy::OpenBolt::Error.new(message: "Option #{key} must be a boolean 'true' or 'false'. Current value: #{value}") unless ['true', 'false'].include?(value)
            value = value == 'true'
          end
          raise Proxy::OpenBolt::Error.new(message: "Option #{key} must be a boolean true for false. It appears to be #{value.class}.") unless [TrueClass, FalseClass].include?(value.class)
        when :string
          value = value.strip
          raise Proxy::OpenBolt::Error.new(message: "Option #{key} must have a value when the option is specified.") if value.empty?
        when Array
          value = value.strip
          raise Proxy::OpenBolt::Error.new(message: "Option #{key} must have one of the following values: #{OPENBOLT_OPTIONS[key][:type]}") unless OPENBOLT_OPTIONS[key][:type].include?(value)
        end
        [key, value]
      end.to_h
      logger.info("Final options: #{scrub(options, options.inspect.to_s)}")

      ### Run the task ###
      task = TaskJob.new(name, params, options, targets)
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

    # Anything that needs to run an OpenBolt CLI command should use this.
    # At the moment, the full output is held in memory and passed back.
    # If this becomes a problem, we can stream to disk and point to it.
    #
    # For task runs, the log goes to stderr and the result to stdout when
    # --format json is specified. At some point, figure out how to make
    # OpenBolt's logger log to a file instead without having to have a special
    # project config file.
    def openbolt(command)
      env = { 'BOLT_GEM' => 'true', 'BOLT_DISABLE_ANALYTICS' => 'true' }
      Open3.capture3(env, *command.split)
    end

    # Probably needs to go in a utils class somewhere
    # Used only for display text that may contain sensitive OpenBolt
    # options values. Should to be used to pass anything to the CLI.
    def scrub(options, text)
      sensitive = options.select { |key, _| OPENBOLT_OPTIONS[key] && OPENBOLT_OPTIONS[key][:sensitive] }
      sensitive.each { |_, value| text = text.gsub(value, '*****') }
      text
    end
  end
end
