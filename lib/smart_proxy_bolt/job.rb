require 'thread'
require 'smart_proxy_bolt/result'

module Proxy::Bolt
  class Job
    attr_accessor :id
    attr_reader :name, :parameters, :transport, :options, :status

    # Valid statuses are
    #  :pending - waiting to run
    #  :running - in progress
    #  :success - job finished as was completely successful
    #  :failure - job finished and had one or more failures
    #  :exception - command exited with an unexpected code

    def initialize(name, parameters, transport, options)
      @id         = nil
      @name       = name
      @parameters = parameters
      @transport  = transport
      @options    = options
      @status     = :pending
      @mutex      = Mutex.new
    end

    def execute
      raise NotImplementedError, "You must call #execute on a subclass of Job"
    end

    # Called by worker. The 'execute' function should return a
    # Proxy::Bolt::Result object
    def process
      update_status(:running)
      begin
        result = execute
        update_status(result.status)
        store_result(result)
      rescue => e
        # This should never happen, but just in case we made a coding error,
        # expose something in the result.
        update_status(:exception)
        store_result(e)
      end
    end

    def update_status(value)
      @mutex.synchronize { @status = value }
    end

    def store_result(value)
      results_file = "#{Proxy::Bolt::Plugin.settings.log_dir}/#{@id}.json"
      File.open(results_file, 'w') { |f| f.write(value.to_json) }
    end

    # At the moment, always read back from the file so we don't store a bunch
    # of huge results in memory. Once we are database-backed, this is less
    # cumbersome and problematic.
    def result
      results_file = "#{Proxy::Bolt::Plugin.settings.log_dir}/#{@id}.json"
      JSON.parse(File.read(results_file))
    end
  end
end
