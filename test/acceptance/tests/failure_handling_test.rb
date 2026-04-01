require_relative '../acceptance_helper'

class FailureHandlingTest < AcceptanceTestCase
  # Failing task status and result structure are covered by
  # JobStatusTest#test_failed_job_reaches_failure and
  # ResultsAndArtifactsTest#test_result_for_failed_task.
  # This file focuses on input validation errors.

  def test_nonexistent_task
    payload = {
      'name' => 'acceptance::does_not_exist',
      'parameters' => {},
      'targets' => transport_targets,
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for nonexistent task'
    assert parsed['error']['message'].include?('not found'),
      "Expected 'not found' in error, got: #{parsed['error']['message']}"
  end

  def test_missing_required_parameter
    payload = {
      'name' => 'acceptance::complex_params',
      'parameters' => { 'array_param' => ['item'] },
      'targets' => transport_targets,
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for missing required parameter'
    assert parsed['error']['message'].include?('Missing required'),
      "Expected 'Missing required' in error, got: #{parsed['error']['message']}"
  end

  def test_unknown_parameter
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => { 'nonexistent_param' => 'value' },
      'targets' => transport_targets,
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for unknown parameter'
    assert parsed['error']['message'].include?('Unknown parameters'),
      "Expected 'Unknown parameters' in error, got: #{parsed['error']['message']}"
  end

  def test_unknown_option
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => {},
      'targets' => transport_targets,
      'options' => transport_options.merge('nonexistent_option' => 'value'),
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for unknown option'
    assert parsed['error']['message'].include?('Invalid options'),
      "Expected 'Invalid options' in error, got: #{parsed['error']['message']}"
  end

  def test_empty_targets
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => {},
      'targets' => [],
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for empty targets'
    assert parsed['error']['message'].include?('empty'),
      "Expected 'empty' in error, got: #{parsed['error']['message']}"
  end

  def test_invalid_json_body
    request = Net::HTTP::Post.new('/openbolt/launch/task')
    request['Content-Type'] = 'application/json'
    request.body = 'this is not json'
    response = http_client.request(request)
    parsed = JSON.parse(response.body)
    assert parsed.key?('error'), 'Expected error for invalid JSON body'
    assert parsed['error']['message'].include?('Invalid JSON'),
      "Expected 'Invalid JSON' in error, got: #{parsed['error']['message']}"
  end

  def test_missing_required_fields
    payload = { 'name' => 'acceptance::noop_task' }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for missing required fields'
  end

  def test_blank_required_parameter_treated_as_missing
    # normalize_values strips empty strings, so a blank required parameter
    # should fail the same way as a missing one
    payload = {
      'name' => 'acceptance::complex_params',
      'parameters' => {
        'required_string' => '',
        'array_param' => ['item'],
      },
      'targets' => transport_targets,
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for blank required parameter'
    assert parsed['error']['message'].include?('Missing required'),
      "Expected 'Missing required' in error, got: #{parsed['error']['message']}"
  end

  def test_whitespace_only_targets_treated_as_empty
    payload = {
      'name' => 'acceptance::noop_task',
      'parameters' => {},
      'targets' => ['  ', ''],
      'options' => transport_options,
    }
    _response, parsed = api_post('/launch/task', payload)
    assert parsed.key?('error'), 'Expected error for whitespace-only targets'
    assert parsed['error']['message'].include?('empty'),
      "Expected 'empty' in error, got: #{parsed['error']['message']}"
  end
end
