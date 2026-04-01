require_relative '../acceptance_helper'

class ResultsAndArtifactsTest < AcceptanceTestCase
  def test_result_structure
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert_equal 'success', result['status']
    assert_equal 1, result['schema'], 'Expected schema version 1'
    assert result.key?('command'), 'Expected command in result'
    assert result.key?('value'), 'Expected value in result'
    assert result.key?('log'), 'Expected log in result'

    items = result['value']['items']
    assert items.is_a?(Array), "Expected items array, got: #{items.class}"
    assert_equal 2, items.length, "Expected results from both targets, got #{items.length}"

    items.each do |item|
      assert item.key?('target'), 'Expected target in result item'
      assert item.key?('status'), 'Expected status in result item'
      assert item.key?('value'), 'Expected value in result item'
      assert_equal 'success', item['status']
    end
  end

  def test_result_contains_target_names
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    targets_in_result = result['value']['items'].map { |item| item['target'] }
    transport_targets.each do |target|
      # Target names may include or exclude the port in the result
      target_host = target.split(':').first
      assert targets_in_result.any? { |result_target| result_target.include?(target_host) },
             "Expected target #{target_host} in result targets: #{targets_in_result}"
    end
  end

  def test_sensitive_value_scrubbing
    secret_password = 'super_secret_p4ssw0rd'
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('password' => secret_password)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result.key?('command'), 'Expected command field in result'
    assert result['command'].length > 0, 'Command field should not be empty'
    assert !result['command'].include?(secret_password),
           'Password should be scrubbed from result command'
    assert result['command'].include?('*****'),
           'Scrubbed password should be replaced with *****'
  end

  def test_scrubbing_does_not_affect_non_sensitive_options
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('verbose' => true)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result.key?('command'), 'Expected command field in result'
    assert result['command'].include?('--verbose'),
           'Non-sensitive options should appear in the command field'
  end

  def test_sudo_password_scrubbing
    secret = 'sudo_s3cret_pass'
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options.merge('sudo-password' => secret)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert result.key?('command'), 'Expected command field in result'
    assert !result['command'].include?(secret),
           'sudo-password should be scrubbed from result command'
    assert result['command'].include?('*****'),
           'Scrubbed sudo-password should be replaced with *****'
  end

  def test_command_field_contains_task_and_targets
    job_id = launch_task(
      name: 'acceptance::echo',
      targets: transport_targets,
      parameters: { 'message' => 'cmd_check' },
      options: transport_options
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    command = result['command']
    assert command.include?('bolt task run'), 'Command should contain bolt task run'
    assert command.include?('acceptance::echo'), 'Command should contain task name'
    assert command.include?('--format json'), 'Command should contain --format json'
  end

  def test_result_for_failed_task
    job_id = launch_task(
      name: 'acceptance::failing_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert_equal 'failure', result['status']
    assert result.key?('value'), 'Expected value in failed result'
    assert result['value'].is_a?(Hash), "Expected structured value in failed result, got: #{result['value'].class}"
    assert result['value'].key?('items'), 'Expected items key in failed result value'
    assert result.key?('log'), 'Expected log in failed result'
    assert result.key?('command'), 'Expected command in failed result'
  end

  def test_sensitive_scrubbing_on_failed_task
    secret = 'failed_task_secret'
    job_id = launch_task(
      name: 'acceptance::failing_task',
      targets: transport_targets,
      options: transport_options.merge('password' => secret)
    )
    wait_for_job(job_id)

    _response, result = api_get("/job/#{job_id}/result")
    assert_equal 'failure', result['status']
    assert !result['command'].include?(secret),
           'Password should be scrubbed from failed task command'
    assert result['command'].include?('*****'),
           'Scrubbed password should be replaced with ***** in failed task'
  end

  def test_result_not_available_while_running
    # Use a slow task to guarantee the job is still in progress when we fetch
    job_id = launch_task(
      name: 'acceptance::slow_task',
      targets: transport_targets,
      parameters: { 'seconds' => 10 },
      options: transport_options
    )

    _response, parsed = api_get("/job/#{job_id}/result")
    assert parsed.key?('error'),
           "Expected error fetching result of in-progress job, got: #{parsed}"

    wait_for_job(job_id, timeout: 30)
  end

  def test_result_for_nonexistent_job
    fake_id = 'aaaaaaaa-0000-0000-0000-000000000000'
    _response, parsed = api_get("/job/#{fake_id}/result")
    assert parsed.key?('error'), 'Expected error for nonexistent job result'
  end

  def test_artifact_deletion
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)

    _response, parsed = api_delete("/job/#{job_id}/artifacts")
    assert_equal 'deleted', parsed['status']

    # After deletion, the job status should be invalid
    _response, status_parsed = api_get("/job/#{job_id}/status")
    assert_equal 'invalid', status_parsed['status']

    # Result should also be gone
    _response, result_parsed = api_get("/job/#{job_id}/result")
    assert result_parsed.key?('error'), 'Expected error when fetching deleted result'
  end

  def test_delete_nonexistent_artifacts
    fake_id = 'aaaaaaaa-0000-0000-0000-000000000000'
    _response, parsed = api_delete("/job/#{fake_id}/artifacts")
    assert_equal 'not_found', parsed['status']
  end

  def test_delete_with_invalid_job_id
    _response, parsed = api_delete('/job/not-a-valid-uuid!/artifacts')
    assert parsed.key?('error'), 'Expected error for invalid characters in job ID'
  end

  def test_double_delete_returns_not_found
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)

    _response, parsed = api_delete("/job/#{job_id}/artifacts")
    assert_equal 'deleted', parsed['status']

    _response, parsed = api_delete("/job/#{job_id}/artifacts")
    assert_equal 'not_found', parsed['status']
  end
end
