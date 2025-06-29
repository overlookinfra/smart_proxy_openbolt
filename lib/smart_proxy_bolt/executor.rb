require 'concurrent'
require 'singleton'
require 'smart_proxy_bolt/job'
require 'smart_proxy_bolt/task_job'
require 'securerandom'

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
      return :invalid unless @jobs.keys.include?(id)
      @jobs[id]&.status
    end

    def result(id)
      return :invalid unless @jobs.keys.include?(id)
      @jobs[id]&.result
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
  end
end
