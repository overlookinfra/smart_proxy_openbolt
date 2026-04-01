require_relative '../acceptance_helper'

class OptionsTest < AcceptanceTestCase
  def test_verbose_option_appears_in_command
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('verbose' => true)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result['command'].include?('--verbose'),
           "Expected --verbose in command, got: #{result['command']}"
  end

  def test_noop_true_option
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('noop' => true)
    )
    status = wait_for_job(job_id)
    # noop may succeed or fail depending on whether the task supports it,
    # but it should not error out at the proxy level
    assert %w[success failure].include?(status),
           "Expected success or failure with noop, got: #{status}"
  end

  def test_noop_false_option
    # When noop is false, parse_options skips the flag entirely rather than
    # passing --no-noop. The task should run normally.
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('noop' => false)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert !result['command'].include?('--noop'),
           'noop=false should not produce --noop in command'
  end

  def test_run_as_option
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('run-as' => 'openbolt')
    )
    status = wait_for_job(job_id)
    assert %w[success failure].include?(status),
           "Expected success or failure with run-as, got: #{status}"
  end

  def test_log_level_option_appears_in_command
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('log-level' => 'debug')
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result['command'].include?('--log-level'),
           "Expected --log-level in command, got: #{result['command']}"
  end

  def test_log_level_trace_adds_trace_flag
    # trace has special handling: it adds both --log-level=trace and --trace
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('log-level' => 'trace')
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result['command'].include?('--trace'),
           "Expected --trace in command for log-level=trace, got: #{result['command']}"
  end

  def test_tmpdir_option_appears_in_command
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('tmpdir' => '/tmp')
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result['command'].include?('--tmpdir'),
           "Expected --tmpdir in command, got: #{result['command']}"
  end

  def test_boolean_option_as_string
    # The API coerces string "true"/"false" to boolean
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('verbose' => 'true')
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result['command'].include?('--verbose'),
           'String "true" should be coerced and produce --verbose in command'
  end

  def test_invalid_boolean_option_value
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => {},
      'targets' => transport_targets,
      'options' => transport_options.merge('verbose' => 'not_a_boolean'),
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for invalid boolean value'
    assert parsed['error']['message'].include?('boolean'),
           "Expected 'boolean' in error, got: #{parsed['error']['message']}"
  end

  def test_invalid_transport_value
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => {},
      'targets' => transport_targets,
      'options' => transport_options.merge('transport' => 'invalid_transport'),
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for invalid transport value'
  end
end
