require 'thread'

module Proxy::Bolt
  class Job
    attr_accessor :id
    attr_reader :name, :parameters, :transport, :options, :status, :result

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

    # Called by worker. The subclass (e.g. TaskJob) should raise an exception if the
    # result was not completely successful (e.g. task on one of the nodes failed).
    def process
      update_status(:running)
      value = execute
      value = begin
                JSON.parse(value)
              rescue JSON::ParserError
                value
              end
      store_result(value)
      update_status(:success)
    rescue => e
      store_result(e)
      update_status(:failure)
    end

    private

    def update_status(status)
      @mutex.synchronize { @status = status }
    end

    def store_result(value)
      @mutex.synchronize { @result = value }
    end
  end
end
