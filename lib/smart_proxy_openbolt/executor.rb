require 'concurrent'
require 'securerandom'
require 'singleton'
require 'smart_proxy_openbolt/job'
require 'smart_proxy_openbolt/lru_cache'
require 'smart_proxy_openbolt/task_job'

module Proxy::OpenBolt
  class Executor
    include Singleton

    SHUTDOWN_TIMEOUT = 30
    MAX_CACHED_JOBS = 1000

    def initialize
      @pool = Concurrent::FixedThreadPool.new(Plugin.settings.workers.to_i)
      @jobs = LruCache.new(MAX_CACHED_JOBS)
    end

    def add_job(job)
      raise ArgumentError, "Only Job instances can be added" unless job.is_a?(Job)
      id = SecureRandom.uuid
      job.id = id
      @jobs.put(id, job)
      @pool.post { job.process }
      id
    end

    def status(id)
      job = get_job(id)
      return :invalid unless job
      job.status
    end

    def result(id)
      job = get_job(id)
      return :invalid unless job
      job.result
    end

    def remove_job(id)
      @jobs.delete(id)
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

    # Stop accepting tasks and wait for in-flight jobs to finish.
    # If timeout is nil, wait forever.
    def shutdown(timeout = SHUTDOWN_TIMEOUT)
      @pool.shutdown
      @pool.wait_for_termination(timeout)
    end

    private

    def get_job(id)
      cached = @jobs.get(id)
      return cached if cached

      # Look on disk for a past run that may have happened
      file = Proxy::OpenBolt.result_file_path(id)
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
        @jobs.put(id, job)
        job
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end
    end
  end
end
