require 'concurrent'
require 'securerandom'
require 'singleton'
require 'smart_proxy_bolt/job'
require 'smart_proxy_bolt/task_job'

module Proxy::Bolt
  class Executor
    include Singleton

    SHUTDOWN_TIMEOUT = 30

    def initialize
      @pool = Concurrent::FixedThreadPool.new(Proxy::Bolt::Plugin.settings.workers.to_i)
      @jobs = Concurrent::Map.new
    end

    def add_job(job)
      raise ArgumentError, "Only Job instances can be added" unless job.is_a?(Job)
      id = SecureRandom.uuid
      job.id = id
      @jobs[id] = job
      @pool.post { job.process }
      id
    end

    def status(id)
      job = get_job(id)
      return :invalid unless job
      job&.status
    end

    def result(id)
      job = get_job(id)
      return :invalid unless job
      job.result
    end

    # How many workers are currently busy
    def num_running
      @pool.length
    end

    # How many jobs are waiting in the queue
    def queue_length
      @pool.queue_length
    end

    # Total number of jobs completed since proxy start
    def jobs_completed
      @pool.completed_task_count
    end

    # Still accepting and running jobs, or shutting down?
    def running?
      @pool.running?
    end

    # Stop accepting tasks and wait up to SHUTDOWN_TIMEOUT seconds
    # for in-flight jobs to finish. If timeout = nil, wait forever.
    def shutdown(timeout)
      @pool.shutdown
      @pool.wait_for_termination(SHUTDOWN_TIMEOUT)
    end

    private

    def get_job(id)
      return @jobs[id] if @jobs.keys.include?(id)
      # Look on disk for a past run that may have happened
      job = nil
      file = "#{Proxy::Bolt::Plugin.settings.log_dir}/#{id}.json"
      if File.exist?(file)
        begin
          data = JSON.parse(File.read(file))
          return nil if data['schema'].nil? || data['schema'] != 1
          return nil if data['status'].nil?
          # This is only for reading back status and result. Don't try
          # to fill in the other arguments correctly, and don't assume
          # they are there after execution.
          job = Job.new(nil, nil, nil)
          job.id = id
          job.update_status(data['status'].to_sym)
          @jobs[id] = job
        rescue JSON::ParserError
        end
      end
      job
    end
  end
end
