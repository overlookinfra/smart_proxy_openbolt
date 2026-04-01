require 'smart_proxy_openbolt/result'

module Proxy::OpenBolt
  class Job
    include ::Proxy::Log

    attr_accessor :id
    attr_reader :name, :parameters, :options, :status

    # Valid statuses are
    #  :pending - waiting to run
    #  :running - in progress
    #  :success - job finished as was completely successful
    #  :failure - job finished and had one or more failures
    #  :exception - command exited with an unexpected code

    def initialize(name, parameters, options)
      @id         = nil
      @name       = name
      @parameters = parameters
      @options    = options
      @status     = :pending
      @mutex      = Mutex.new
    end

    def execute
      raise NotImplementedError, "You must call #execute on a subclass of Job"
    end

    # Called by worker. The 'execute' function should return a
    # Proxy::OpenBolt::Result object
    def process
      update_status(:running)
      begin
        result = execute
        update_status(result.status)
        store_result(result)
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Catch everything including non-StandardError exceptions (e.g.
        # ScriptError) so the job always gets a terminal status.
        update_status(:exception)
        logger.error("Job #{@id} failed (#{e.class}): #{e.message}")
        logger.debug(e.backtrace.join("\n")) if e.backtrace
        begin
          store_result({ message: e.full_message, backtrace: e.backtrace })
        rescue StandardError => store_error
          logger.error("Job #{@id}: failed to store error result: #{store_error.message}")
          logger.debug(store_error.backtrace.join("\n")) if store_error.backtrace
        end
      end
    end

    def update_status(value)
      @mutex.synchronize { @status = value }
    end

    def store_result(value)
      File.write(Proxy::OpenBolt.result_file_path(@id), value.to_json)
    end

    # Read the result back from disk as a raw JSON string. We avoid parsing
    # and re-serializing since the file is already valid JSON.
    def result
      File.read(Proxy::OpenBolt.result_file_path(@id))
    end
  end
end
