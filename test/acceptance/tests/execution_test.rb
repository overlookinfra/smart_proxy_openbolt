require_relative '../acceptance_helper'

class ExecutionTest < AcceptanceTestCase
  def test_echo_task_with_parameter
    job_id = launch_task(
      name: 'acceptance::echo',
      targets: transport_targets,
      parameters: { 'message' => 'hello from acceptance test' },
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    assert_equal 'success', result['status']
    items = result['value']['items']
    assert items.is_a?(Array), "Expected items array, got: #{items.class}"
    assert_equal 2, items.length, "Expected results from both targets, got #{items.length}"
    items.each do |item|
      assert_equal 'hello from acceptance test', item['value']['message']
    end
  end

  def test_parameterless_task
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    assert_equal 2, items.length, "Expected results from both targets, got #{items.length}"
    items.each do |item|
      assert_equal 'ok', item['value']['status']
    end
  end

  def test_complex_parameters_with_array
    job_id = launch_task(
      name: 'acceptance::complex_params',
      targets: transport_targets,
      parameters: {
        'required_string' => 'test_value',
        'array_param' => ['one', 'two', 'three'],
      },
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    items.each do |item|
      assert_equal 'test_value', item['value']['required_string']
      assert_equal ['one', 'two', 'three'], item['value']['array_param']
    end
  end

  def test_optional_and_default_parameters
    # Omit optional_string and with_default. Task should succeed,
    # and with_default should receive its default value from metadata
    job_id = launch_task(
      name: 'acceptance::complex_params',
      targets: transport_targets,
      parameters: {
        'required_string' => 'present',
        'array_param' => ['item'],
      },
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status, 'Task should succeed without optional parameters'

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    items.each do |item|
      assert_nil item['value']['optional_string'],
                 'Omitted optional parameter should be nil'
      assert_equal 'default_value', item['value']['with_default'],
                   'Parameter with default should receive the default value'
    end
  end

  def test_hash_parameter
    job_id = launch_task(
      name: 'acceptance::complex_params',
      targets: transport_targets,
      parameters: {
        'required_string' => 'hash_test',
        'array_param' => ['item'],
        'hash_param' => { 'key1' => 'value1', 'key2' => 42 },
      },
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    items.each do |item|
      assert_equal({ 'key1' => 'value1', 'key2' => 42 }, item['value']['hash_param'],
                   'Hash parameter should round-trip correctly')
    end
  end

  def test_targets_as_comma_separated_string
    # The API splits comma-separated string targets into an array
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets.join(','),
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    assert_equal 2, items.length,
                 'Comma-separated targets should produce results from both targets'
  end

  def test_mixed_success_and_failure_per_target
    job_id = launch_task(
      name: 'acceptance::target_conditional',
      targets: transport_targets,
      parameters: { 'succeed_on' => 'openbolt-target1' },
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'failure', status, 'Overall job should be failure when any target fails'

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    assert_equal 2, items.length, "Expected results from both targets, got #{items.length}"

    successes = items.select { |item| item['status'] == 'success' }
    failures = items.select { |item| item['status'] == 'failure' }
    assert_equal 1, successes.length, 'Expected exactly one target to succeed'
    assert_equal 1, failures.length, 'Expected exactly one target to fail'
  end

  def test_single_target_execution
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: [transport_targets.first],
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status

    _response, result = api_get("/job/#{job_id}/result")
    items = result['value']['items']
    assert_equal 1, items.length, 'Single target should produce exactly one result'
  end
end
