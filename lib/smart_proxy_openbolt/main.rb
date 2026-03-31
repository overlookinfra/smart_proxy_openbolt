require 'json'
require 'open3'
require 'smart_proxy_openbolt/executor'
require 'smart_proxy_openbolt/error'

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
      :description => 'When enabled, perform host key verification when connecting to targets over SSH.',
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
  SORTED_OPTIONS = OPENBOLT_OPTIONS.sort.to_h.freeze

  @mutex = Mutex.new

  class << self
    def openbolt_options
      SORTED_OPTIONS
    end

    def executor
      @executor ||= Executor.instance
    end

    def validate_job_id!(id)
      return if id =~ /\A[a-f0-9\-]+\z/i
      raise Error.new(message: 'Invalid job ID format')
    end

    def result_file_path(id)
      File.join(Plugin.settings.log_dir, "#{id}.json")
    end

    # /tasks or /tasks/reload
    def tasks(reload: false)
      # If we need to reload, only one instance of the reload
      # should happen at once. Make others wait until it is
      # finished.
      @mutex.synchronize do
        @tasks = nil if reload
        @tasks || reload_tasks
      end
    end

    def reload_tasks
      task_data = {}

      # Get a list of all tasks
      command = ['bolt', 'task', 'show',
                 '--project', Plugin.settings.environment_path,
                 '--format', 'json']
      parsed = openbolt_json(command)
      task_list = parsed['tasks']
      raise Error.new(
        message: "Unexpected output from 'bolt task show': expected 'tasks' to be an array, got #{task_list.class}.",
      ) unless task_list.is_a?(Array)

      # Get metadata for each task
      task_list.each do |task_entry|
        name = task_entry[0]
        command = ['bolt', 'task', 'show', name,
                   '--project', Plugin.settings.environment_path,
                   '--format', 'json']
        result = openbolt_json(command)
        metadata = result['metadata']
        raise Error.new(
          message: "Invalid metadata found for task #{name}",
        ) if metadata.nil?

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
        raise Error.new(message: 'Data passed in to launch_task function is not a hash. This is most likely a bug in the smart_proxy_openbolt plugin. Please file an issue with the maintainers.')
      end
      fields = ['name', 'parameters', 'targets', 'options']
      unless fields.all? { |k| data.keys.include?(k) }
        raise Error.new(message: "You must provide values for 'name', 'parameters', 'targets', and 'options'.")
      end
      name = data['name']
      params = data['parameters'] || {}
      targets = data['targets']
      options = data['options'] || {}

      logger.info("Task: #{name}")
      logger.info("Parameters: #{params.inspect}")
      logger.info("Targets: #{targets.inspect}")
      logger.info("Options: #{scrub(options, options.inspect)}")

      # Validate name
      raise Error.new(message: "You must provide a value for 'name'.") unless name.is_a?(String) && !name.empty?
      raise Error.new(message: "Task #{name} not found.") unless tasks.keys.include?(name)

      # Validate parameters
      raise Error.new(message: "The 'parameters' value should be a hash.") unless params.is_a?(Hash)
      extra = params.keys - tasks[name]['parameters'].keys
      raise Error.new(message: "Unknown parameters: #{extra}") unless extra.empty?

      # Normalize parameters, ensuring blank values are not passed
      params = normalize_values(params)
      logger.info("Normalized parameters: #{params.inspect}")

      # Check required parameters after normalization so blank values are caught
      missing = []
      tasks[name]['parameters'].each do |k, v|
        next if v['type']&.start_with?('Optional[')
        next if v.key?('default')
        missing << k unless params.key?(k)
      end
      raise Error.new(message: "Missing required parameters: #{missing}") unless missing.empty?

      # Validate targets
      raise Error.new(message: "The 'targets' value should be a string or an array.") unless targets.is_a?(String) || targets.is_a?(Array)
      if targets.is_a?(Array)
        raise Error.new(message: "All target values must be strings.") unless targets.all? { |target| target.is_a?(String) }
        targets = targets.map(&:strip).reject(&:empty?)
      else
        targets = targets.split(',').map(&:strip).reject(&:empty?)
      end
      raise Error.new(message: "The 'targets' value should not be empty.") if targets.empty?

      # Validate options
      raise Error.new(message: "The 'options' value should be a hash.") unless options.is_a?(Hash)
      unknown = options.keys - OPENBOLT_OPTIONS.keys
      raise Error.new(message: "Invalid options specified: #{unknown}") unless unknown.empty?

      # Normalize options, removing blank values
      options = normalize_values(options)
      logger.info("Normalized options: #{scrub(options, options.inspect)}")
      OPENBOLT_OPTIONS.each { |key, value| options[key] ||= value[:default] if value.key?(:default) }
      logger.info("Options with required defaults: #{scrub(options, options.inspect)}")

      # Validate option types
      options = options.map do |key, value|
        type = OPENBOLT_OPTIONS[key][:type]
        case type
        when :boolean
          if value.is_a?(String)
            value = value.downcase.strip
            raise Error.new(message: "Option #{key} must be a boolean 'true' or 'false'. Current value: #{value}") unless ['true', 'false'].include?(value)
            value = value == 'true'
          end
          raise Error.new(message: "Option #{key} must be a boolean true or false. It appears to be #{value.class}.") unless [TrueClass, FalseClass].include?(value.class)
        when :string
          raise Error.new(message: "Option #{key} must have a value when the option is specified.") if value.to_s.empty?
        when Array
          raise Error.new(message: "Option #{key} must have one of the following values: #{OPENBOLT_OPTIONS[key][:type]}") unless OPENBOLT_OPTIONS[key][:type].include?(value.to_s)
        end
        [key, value]
      end.to_h
      logger.info("Final options: #{scrub(options, options.inspect)}")

      ### Run the task ###
      task = TaskJob.new(name, params, options, targets)
      id = executor.add_job(task)

      { id: id }.to_json
    end

    # /job/:id/status
    def get_status(id)
      validate_job_id!(id)
      { status: executor.status(id) }.to_json
    end

    # /job/:id/result
    def get_result(id)
      validate_job_id!(id)
      result = executor.result(id)
      return result if result.is_a?(String)
      raise Error.new(message: "Job not found: #{id}") if result == :invalid
      result.to_json
    rescue Errno::ENOENT
      raise Error.new(message: "Result file not found for job: #{id}")
    end

    # DELETE /job/:id/artifacts
    def delete_artifacts(id)
      validate_job_id!(id)

      file_path = result_file_path(id)
      real_path = File.realpath(file_path)
      expected_dir = File.realpath(Plugin.settings.log_dir)
      raise Error.new(message: 'Invalid file path') unless real_path.start_with?(expected_dir)

      File.delete(file_path)
      executor.remove_job(id)
      logger.info("Deleted artifacts for job #{id}")
      { status: 'deleted', job_id: id }.to_json
    rescue Errno::ENOENT
      logger.warning("Artifacts not found for job #{id}")
      { status: 'not_found', job_id: id }.to_json
    end

    # Runs an openbolt command that is expected to produce JSON on stdout.
    # Returns the parsed JSON hash. Raises CliError on non-zero exit or
    # Error on JSON parse failure.
    def openbolt_json(command)
      stdout, stderr, exitcode = openbolt(command)
      unless exitcode.zero?
        raise CliError.new(
          message:  "Error running '#{command.first(4).join(' ')}'.",
          exitcode: exitcode,
          stdout:   stdout,
          stderr:   stderr,
          command:  command.join(' '),
        )
      end
      begin
        JSON.parse(stdout)
      rescue JSON::ParserError => e
        raise Error.new(
          message:   "Error parsing JSON output from '#{command.first(4).join(' ')}'.",
          exception: e,
        )
      end
    end

    # Anything that needs to run an OpenBolt CLI command should use this.
    # At the moment, the full output is held in memory and passed back.
    # If this becomes a problem, we can stream to disk and point to it.
    #
    # For task runs, the log goes to stderr and the result to stdout when
    # --format json is specified. At some point, figure out how to make
    # OpenBolt's logger log to a file instead without having to have a special
    # project config file.
    # Returns [stdout, stderr, exitcode]. Handles the case where the
    # process is killed by a signal (exitstatus is nil).
    def openbolt(command)
      env = { 'BOLT_GEM' => 'true', 'BOLT_DISABLE_ANALYTICS' => 'true' }
      stdout, stderr, status = Open3.capture3(env, *command)
      exitcode = status.exitstatus
      if exitcode.nil?
        # 128 + signal follows the Unix/shell convention for signal exit codes.
        exitcode = 128 + (status.termsig || 0)
        stderr = "Process was killed by signal #{status.termsig}.\n#{stderr}"
      end
      [stdout, stderr, exitcode]
    end

    # Used only for display text that may contain sensitive OpenBolt
    # options values. Should not be used to pass anything to the CLI.
    def scrub(options, text)
      sensitive = options.select { |key, _| OPENBOLT_OPTIONS[key] && OPENBOLT_OPTIONS[key][:sensitive] }
      sensitive.each do |_, value|
        redact = value.to_s
        next if redact.empty?
        text = text.gsub(redact, '*****')
      end
      text
    end
  end
end
