require 'test_helper'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/task_job'

class TaskJobTest < SmartProxyOpenboltTestCase
  def test_parse_parameters_string_values
    job = Proxy::OpenBolt::TaskJob.new('task', { 'name' => 'hello' }, {}, ['node1'])
    params = job.parse_parameters

    assert_equal ['name=hello'], params
  end

  def test_parse_parameters_with_spaces_in_value
    job = Proxy::OpenBolt::TaskJob.new('task', { 'msg' => 'hello world' }, {}, ['node1'])
    params = job.parse_parameters

    assert_equal ['msg=hello world'], params
  end

  def test_parse_parameters_array_values
    job = Proxy::OpenBolt::TaskJob.new('task', { 'list' => ['a', 'b'] }, {}, ['node1'])
    params = job.parse_parameters

    assert_equal ['list=["a","b"]'], params
  end

  def test_parse_parameters_hash_values
    job = Proxy::OpenBolt::TaskJob.new('task', { 'data' => { 'k' => 'v' } }, {}, ['node1'])
    params = job.parse_parameters

    assert_equal ['data={"k":"v"}'], params
  end

  def test_parse_parameters_empty
    job = Proxy::OpenBolt::TaskJob.new('task', {}, {}, ['node1'])
    assert_equal [], job.parse_parameters
  end

  def test_parse_options_boolean_true
    job = Proxy::OpenBolt::TaskJob.new('task', {}, { 'verbose' => true }, ['node1'])
    opts = job.parse_options

    assert opts.include?('--verbose')
  end

  def test_parse_options_boolean_false
    job = Proxy::OpenBolt::TaskJob.new('task', {}, { 'host-key-check' => false }, ['node1'])
    opts = job.parse_options

    assert opts.include?('--no-host-key-check')
  end

  def test_parse_options_noop_false_skipped
    job = Proxy::OpenBolt::TaskJob.new('task', {}, { 'noop' => false }, ['node1'])
    opts = job.parse_options

    assert_equal [], opts
  end

  def test_parse_options_string_value
    job = Proxy::OpenBolt::TaskJob.new('task', {}, { 'user' => 'admin' }, ['node1'])
    opts = job.parse_options

    assert opts.include?('--user=admin')
  end

  def test_parse_options_trace_special_case
    job = Proxy::OpenBolt::TaskJob.new('task', {}, { 'log-level' => 'trace' }, ['node1'])
    opts = job.parse_options

    assert opts.include?('--log-level=trace')
    assert opts.include?('--trace')
  end

  def test_parse_options_nil_options
    job = Proxy::OpenBolt::TaskJob.new('task', {}, nil, ['node1'])
    assert_equal [], job.parse_options
  end

  def test_parse_options_empty
    job = Proxy::OpenBolt::TaskJob.new('task', {}, {}, ['node1'])
    assert_equal [], job.parse_options
  end

  def test_execute_returns_result
    Proxy::OpenBolt.stubs(:openbolt).returns(['{"items":[]}', 'log', 0])

    job = Proxy::OpenBolt::TaskJob.new('my::task', {}, {}, ['node1'])
    result = job.execute

    assert result.is_a?(Proxy::OpenBolt::Result)
    assert_equal :success, result.status
  end

  def test_execute_scrubs_sensitive_options
    Proxy::OpenBolt.stubs(:openbolt).returns(['{"items":[]}', 'password=secret123 in log', 0])

    job = Proxy::OpenBolt::TaskJob.new('my::task', {}, { 'password' => 'secret123' }, ['node1'])
    result = job.execute

    assert !result.log.include?('secret123'), 'Sensitive values should be scrubbed from log'
    assert result.log.include?('*****'), 'Sensitive values should be replaced with *****'
  end

  def test_execute_handles_signal_killed_process
    Proxy::OpenBolt.stubs(:openbolt).returns(['', "Process was killed by signal 9.\nsome output", 137])

    job = Proxy::OpenBolt::TaskJob.new('my::task', {}, {}, ['node1'])
    result = job.execute

    assert_equal :exception, result.status
    assert result.value.include?('signal 9'), 'Should mention the signal'
  end
end
