require_relative '../acceptance_helper'

# Task discovery is transport-agnostic. It only needs the OpenBolt CLI and
# the fixtures directory. No live SSH target is required.
class TaskDiscoveryTest < AcceptanceTestCase
  # Only require the proxy to be reachable, not a specific transport.
  def skip_unless_proxy
    omit('Proxy not reachable') unless self.class.proxy_available?
  end

  def test_tasks_returns_fixture_tasks
    _response, tasks = api_get('/tasks')

    expected_tasks = %w[
      acceptance::echo acceptance::noop_task acceptance::failing_task
      acceptance::complex_params acceptance::target_conditional acceptance::slow_task
    ]
    expected_tasks.each do |name|
      assert tasks.key?(name), "Expected task '#{name}' in task list, got: #{tasks.keys}"
    end
  end

  def test_tasks_returns_descriptions
    _response, tasks = api_get('/tasks')

    assert_equal 'Echo a message back with the hostname', tasks['acceptance::echo']['description']
    assert_equal 'A task that always fails', tasks['acceptance::failing_task']['description']
    assert_equal 'A no-op task that returns a status', tasks['acceptance::noop_task']['description']
  end

  def test_echo_task_has_correct_parameters
    _response, tasks = api_get('/tasks')
    echo = tasks['acceptance::echo']

    assert echo, 'acceptance::echo task not found'
    assert echo['parameters'].key?('message'), 'Expected message parameter'
    assert_equal 'String', echo['parameters']['message']['type']
  end

  def test_complex_params_task_has_expected_parameter_types
    _response, tasks = api_get('/tasks')
    complex = tasks['acceptance::complex_params']

    assert complex, 'acceptance::complex_params task not found'
    params = complex['parameters']
    assert_equal 'String', params['required_string']['type']
    assert_equal 'Optional[String]', params['optional_string']['type']
    assert_equal 'Array', params['array_param']['type']
    assert_equal 'default_value', params['with_default']['default']
    assert_equal 'Optional[Hash]', params['hash_param']['type']
  end

  def test_noop_task_has_no_parameters
    _response, tasks = api_get('/tasks')
    noop = tasks['acceptance::noop_task']

    assert noop, 'acceptance::noop_task not found'
    assert noop['parameters'].empty?, "Expected no parameters, got: #{noop['parameters'].keys}"
  end

  def test_tasks_reload_returns_tasks
    response, tasks = api_get('/tasks/reload')
    assert response.is_a?(Net::HTTPSuccess), "Expected success, got #{response.code}"
    assert tasks.key?('acceptance::echo'), 'Expected acceptance::echo after reload'
  end

  def test_tasks_reload_returns_same_tasks_as_tasks
    _response, tasks = api_get('/tasks')
    _response, reloaded = api_get('/tasks/reload')

    assert_equal tasks.keys.sort, reloaded.keys.sort,
                 'Reloaded tasks should have the same task names'
  end

  def test_tasks_options_returns_openbolt_options
    response, options = api_get('/tasks/options')
    assert response.is_a?(Net::HTTPSuccess), "Expected success, got #{response.code}"

    # Verify key options are present
    %w[transport user password host-key-check private-key verbose noop].each do |key|
      assert options.key?(key), "Expected '#{key}' in options, got: #{options.keys}"
    end
  end

  def test_tasks_options_transport_metadata
    _response, options = api_get('/tasks/options')
    transport = options['transport']

    assert transport.key?('type'), 'Expected type in transport option'
    assert transport['type'].include?('ssh'), 'Expected ssh in transport types'
    assert transport.key?('default'), 'Expected default in transport option'
    assert_equal 'ssh', transport['default']
  end

  def test_tasks_options_sensitive_flag
    _response, options = api_get('/tasks/options')

    assert_equal true, options['password']['sensitive'],
                 'password should be marked sensitive'
    assert_equal true, options['sudo-password']['sensitive'],
                 'sudo-password should be marked sensitive'
    assert_equal false, options['user']['sensitive'],
                 'user should not be marked sensitive'
    assert_equal false, options['verbose']['sensitive'],
                 'verbose should not be marked sensitive'
  end
end
