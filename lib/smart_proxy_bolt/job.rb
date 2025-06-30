require 'net/http'
require 'smart_proxy_bolt/result'
require 'thread'

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
        store_result({message: e.full_message, backtrace: e.backtrace})
      end
    end

    def update_status(value)
      @mutex.synchronize { @status = value }
    end

    def store_result(value)
      # On disk
      results_file = "#{Proxy::Bolt::Plugin.settings.log_dir}/#{@id}.json"
      File.open(results_file, 'w') { |f| f.write(value.to_json) }

      # Send to reports API
      reports = get_reports(value)

      # TODO: Figure out how to authenticate with the /api/config_reports endpoint
      reports.each do |report|
        foreman = Proxy::SETTINGS.foreman_url
        # Send it
        puts foreman
      end
    end

    def log_item(text, level)
      { 
        'log': {
          'sources': {
            'source': 'Bolt'
          },
          'messages': {
            'message': text
          },
          'level': level
        }
      }
    end

    def get_reports(value)
      command = value.command
      log = value.log
      items = value.value['items']
      return nil if items.nil?
      timestamp = Time.now.utc

      source = { 'sources': { 'source': 'Bolt' } }
      items.map do |item|
        target = item['target']
        status = item['status']
        data = item['value']
        message = item['message']
        logs = [log_item("Command: #{command}", 'info')]
        if data['_error']
          kind = data.dig('_error','kind')
          msg = data.dig('_error', 'msg')
          issue_code = data.dig('_error', 'issue_code')
          logs << log_item("Error kind: #{kind}", 'error')
          logs << log_item("Error mesage: #{msg}", 'error')
          logs << log_item("Error issue code: #{issue_code}", 'error')
        end
        logs << log_item("Result: #{data}", 'info')
        logs << log_item("Task run log: #{log}", 'info') if log
        logs << log_item("Message: #{message}", 'info') if message
        {
          'config_report': {
            'host': target,
            'reported_at': timestamp,
            'status': {
              "applied": status == 'success' ? 1 : 0,
              "failed": status == 'failure' ? 1 : 0,
            },
            'logs': logs
          }
        }
      end
      items
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
