require 'test_helper'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/job'
require 'smart_proxy_openbolt/result'

class JobTest < SmartProxyOpenboltTestCase
  def test_initial_status_is_pending
    job = Proxy::OpenBolt::Job.new('task_name', {}, {})
    assert_equal :pending, job.status
  end

  def test_execute_raises_not_implemented
    job = Proxy::OpenBolt::Job.new('task_name', {}, {})
    assert_raise(NotImplementedError) { job.execute }
  end

  def test_process_runs_execute_and_updates_status
    job = TestableJob.new('task_name', {}, {})
    job.id = 'test-uuid'
    job.process

    assert_equal :success, job.status
  end

  def test_process_stores_result_to_disk
    job = TestableJob.new('task_name', {}, {})
    job.id = 'test-uuid'
    job.process

    result_file = File.join(@test_log_dir, 'test-uuid.json')
    assert File.exist?(result_file), 'Result file should be written to disk'

    content = JSON.parse(File.read(result_file))
    assert_equal 'success', content['status']
  end

  def test_process_handles_exception_in_execute
    job = FailingJob.new('task_name', {}, {})
    job.id = 'failing-uuid'
    job.process

    assert_equal :exception, job.status

    result_file = File.join(@test_log_dir, 'failing-uuid.json')
    content = JSON.parse(File.read(result_file))
    assert content['message'].include?('intentional test error')
  end

  def test_process_survives_store_result_failure
    job = DoubleFailingJob.new('task_name', {}, {})
    job.id = 'double-fail-uuid'

    # Should not raise -- the inner rescue catches the store_result failure
    job.process

    assert_equal :exception, job.status
  end

  def test_result_reads_from_disk
    job = TestableJob.new('task_name', {}, {})
    job.id = 'read-test-uuid'
    job.process

    result = JSON.parse(job.result)
    assert_equal 'success', result['status']
  end

  private

  # Minimal Job subclass that returns a successful Result
  class TestableJob < Proxy::OpenBolt::Job
    def execute
      Proxy::OpenBolt::Result.new('test command', '{"items":[]}', 'log output', 0)
    end
  end

  # Job subclass that raises during execute
  class FailingJob < Proxy::OpenBolt::Job
    def execute
      raise 'intentional test error'
    end
  end

  # Job subclass where both execute and store_result fail
  class DoubleFailingJob < Proxy::OpenBolt::Job
    def execute
      raise 'execute blew up'
    end

    def store_result(_value)
      raise 'disk is full'
    end
  end
end
