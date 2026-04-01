require_relative '../acceptance_helper'

class JobStatusTest < AcceptanceTestCase
  def test_status_while_running
    # Use a slow task to guarantee the job is still in progress when we poll
    job_id = launch_task(
      name: 'acceptance::slow_task',
      targets: transport_targets,
      parameters: { 'seconds' => 10 },
      options: transport_options
    )

    status = poll_job_status(job_id)
    assert %w[pending running].include?(status),
           "Expected pending or running for in-progress job, got: #{status}"

    terminal = wait_for_job(job_id, timeout: 30)
    assert_equal 'success', terminal
  end

  def test_successful_job_reaches_success
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'success', status
  end

  def test_failed_job_reaches_failure
    job_id = launch_task(
      name: 'acceptance::failing_task',
      targets: transport_targets,
      options: transport_options
    )
    status = wait_for_job(job_id)
    assert_equal 'failure', status
  end

  def test_invalid_job_id_format
    _response, parsed = api_get('/job/not-a-valid-uuid!/status')
    assert parsed.key?('error'), 'Expected error for invalid characters in job ID'
  end

  def test_job_id_with_shell_metacharacters
    _response, parsed = api_get('/job/$(whoami)/status')
    assert parsed.key?('error'), 'Expected error for job ID with shell metacharacters'
  end

  def test_unknown_job_id
    _response, parsed = api_get('/job/aaaaaaaa-0000-0000-0000-000000000000/status')
    assert_equal 'invalid', parsed['status']
  end

  def test_status_after_artifact_deletion
    job_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    wait_for_job(job_id)
    api_delete("/job/#{job_id}/artifacts")

    _response, parsed = api_get("/job/#{job_id}/status")
    assert_equal 'invalid', parsed['status'],
                 'Status should be invalid after artifact deletion'
  end
end
