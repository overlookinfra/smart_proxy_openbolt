require_relative '../acceptance_helper'

class ConcurrencyTest < AcceptanceTestCase
  def test_concurrent_task_execution
    job_ids = (1..3).map do |index|
      launch_task(
        name: 'acceptance::echo',
        targets: transport_targets,
        parameters: { 'message' => "concurrent-#{index}" },
        options: transport_options
      )
    end

    statuses = wait_for_jobs(job_ids)
    assert statuses.all?('success'),
      "Expected all jobs to succeed, got: #{statuses}"

    # Verify each job has its own distinct result
    job_ids.each_with_index do |job_id, index|
      _response, result = api_get("/job/#{job_id}/result")
      items = result['value']['items']
      assert_equal 2, items.length,
        "Job #{index + 1} should have results from both targets"
      items.each do |item|
        assert_equal "concurrent-#{index + 1}", item['value']['message'],
          "Job #{index + 1} should have its own message"
      end
    end
  end

  def test_concurrent_mixed_success_and_failure
    success_id = launch_task(
      name: 'acceptance::noop_task',
      targets: transport_targets,
      options: transport_options
    )
    failure_id = launch_task(
      name: 'acceptance::failing_task',
      targets: transport_targets,
      options: transport_options
    )

    statuses = wait_for_jobs([success_id, failure_id])
    assert_equal 'success', statuses[0], 'Successful task should not be affected by failing task'
    assert_equal 'failure', statuses[1], 'Failing task should fail independently'
  end

  def test_concurrent_jobs_have_unique_ids
    job_ids = (1..5).map do
      launch_task(
        name: 'acceptance::noop_task',
        targets: transport_targets,
        options: transport_options
      )
    end

    assert_equal job_ids.uniq.length, job_ids.length,
      "All job IDs should be unique: #{job_ids}"
    wait_for_jobs(job_ids)
  end
end
