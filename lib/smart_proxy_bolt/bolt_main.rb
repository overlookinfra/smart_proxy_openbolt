require 'open3'
require 'smart_proxy_bolt/executor'

module Proxy::Bolt
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self

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
      rescue Json::ParserError => e
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
        if metadata.nil? || metadata['parameters'].nil? || metadata['description'].nil?
          @tasks = nil
          raise Proxy::Bolt::Error.new(
            message: "Invalid metadata found for task #{name}",
            output: output,
            command: command,
          )
        end
        @tasks[name] = {
          'description' => metadata['description'],
          'parameters'  => metadata['parameters'],
        }
      end

      @tasks
    end

    def run_task(data)
      # Validation
      unless data.is_a?(Hash)
        raise Proxy::Bolt::Error.new(message: 'Data passed in to run_task function is not a hash. This is most likely a bug in the smart_proxy_bolt plugin. Please file an issue with the maintainers.').to_json
      end
      fields = ['name', 'parameters', 'targets']
      unless fields.all? { |k| data.keys.include?(k) }
        raise Proxy::Bolt::Error.new(message: "You must provide values for 'name', 'parameters', and 'targets'.")
      end
      name = data['name']
      params = data['parameters']
      targets = data['targets']
      # Validate name
      raise Proxy::Bolt::Error.new(message: "You must provide a value for 'name'.") unless name.is_a?(String) && !name.empty?
      raise Proxy::Bolt::Error.new(message: "Task #{name} not found.") unless tasks.keys.include?(name)
      
      # Validate parameters
      raise Proxy::Bolt::Error.new(message: "The 'parameters' key should be a hash.") unless params.is_a?(Hash)
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
      
      # Run the task
      task = TaskJob.new(name, params, targets)
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
      return {
        error: @executor.error(id)
      }.to_json
    end

    private

    def bolt(command)
      env = { 'BOLT_GEM' => '1' }
      Open3.capture2e(env, *command.split)
    end
  end
end
