require 'test_helper'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/executor'
require 'smart_proxy_openbolt/task_job'
require 'smart_proxy_openbolt/result'

class ExecutorTest < SmartProxyOpenboltTestCase
  def setup
    super
    @executor = Proxy::OpenBolt::Executor.instance
    # Clear jobs between tests
    @executor.instance_variable_set(:@jobs, Proxy::OpenBolt::LruCache.new(Proxy::OpenBolt::Executor::MAX_CACHED_JOBS))
  end

  def test_add_job_returns_uuid
    job = make_stubbed_task_job
    id = @executor.add_job(job)

    assert id.is_a?(String)
    assert_match(/\A[a-f0-9\-]{36}\z/, id)
  end

  def test_add_job_sets_job_id
    job = make_stubbed_task_job
    id = @executor.add_job(job)

    assert_equal id, job.id
  end

  def test_add_job_rejects_non_job
    assert_raise(ArgumentError) { @executor.add_job('not a job') }
  end

  def test_status_returns_invalid_for_unknown_id
    assert_equal :invalid, @executor.status('nonexistent-uuid')
  end

  def test_result_returns_invalid_for_unknown_id
    assert_equal :invalid, @executor.result('nonexistent-uuid')
  end

  def test_status_reads_from_disk_when_not_cached
    id = 'disk-test-uuid'
    result_data = {
      'command' => 'bolt task run foo',
      'status' => 'success',
      'value' => { 'items' => [] },
      'log' => 'log output',
      'schema' => 1
    }
    File.write(File.join(@test_log_dir, "#{id}.json"), result_data.to_json)

    assert_equal :success, @executor.status(id)
  end

  def test_result_reads_from_disk_when_not_cached
    id = 'disk-result-uuid'
    result_data = {
      'command' => 'bolt task run foo',
      'status' => 'success',
      'value' => { 'items' => [{ 'target' => 'node1' }] },
      'log' => 'some log',
      'schema' => 1
    }
    File.write(File.join(@test_log_dir, "#{id}.json"), result_data.to_json)

    result = JSON.parse(@executor.result(id))
    assert_equal 'success', result['status']
    assert_equal [{ 'target' => 'node1' }], result['value']['items']
    assert_equal 'some log', result['log']
  end

  def test_status_returns_cached_job
    job = make_stubbed_task_job
    id = @executor.add_job(job)

    # Job was just added, should be :pending from the in-memory cache
    assert_equal :pending, @executor.status(id)
  end

  def test_get_job_returns_invalid_for_wrong_schema
    id = 'bad-schema-uuid'
    File.write(File.join(@test_log_dir, "#{id}.json"), { 'schema' => 99, 'status' => 'success' }.to_json)

    assert_equal :invalid, @executor.status(id)
  end

  def test_get_job_returns_invalid_for_missing_status
    id = 'no-status-uuid'
    File.write(File.join(@test_log_dir, "#{id}.json"), { 'schema' => 1 }.to_json)

    assert_equal :invalid, @executor.status(id)
  end

  def test_get_job_returns_invalid_for_invalid_json
    id = 'bad-json-uuid'
    File.write(File.join(@test_log_dir, "#{id}.json"), 'not valid json{{{')

    assert_equal :invalid, @executor.status(id)
  end

  def test_get_job_returns_invalid_for_nonexistent_file
    assert_equal :invalid, @executor.status('does-not-exist-anywhere')
  end

  def make_stubbed_task_job
    job = Proxy::OpenBolt::TaskJob.new('test::task', {}, {}, ['node1'])
    Proxy::OpenBolt.stubs(:openbolt).returns(['{"items":[]}', '', 0])
    job
  end
end
