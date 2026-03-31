require 'test_helper'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/api'

class ApiTest < SmartProxyOpenboltTestCase
  include Rack::Test::Methods

  def app
    Proxy::OpenBolt::Api.new
  end

  def setup
    super
    # Prevent the background task reload thread from running
    Proxy::OpenBolt.stubs(:tasks).returns({})
  end

  def test_get_tasks_returns_json
    Proxy::OpenBolt.stubs(:tasks).returns({ 'my::task' => { 'description' => 'test' } })

    get '/tasks'
    assert last_response.ok?
    parsed = JSON.parse(last_response.body)
    # Verify the response is the JSON-serialized return value of tasks(),
    # not just that it's valid JSON
    assert_equal 'test', parsed['my::task']['description']
  end

  def test_get_tasks_reload_passes_reload_flag
    Proxy::OpenBolt.expects(:tasks).with(reload: true).returns({})

    get '/tasks/reload'
    assert last_response.ok?
  end

  def test_get_tasks_options_returns_json
    Proxy::OpenBolt.stubs(:openbolt_options).returns({ 'transport' => { type: 'string' } })

    get '/tasks/options'
    assert last_response.ok?
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('transport')
  end

  def test_post_launch_task_parses_body_and_passes_to_launch_task
    expected_data = { 'name' => 'my::task', 'targets' => 'node1', 'parameters' => {}, 'options' => {} }

    Proxy::OpenBolt.expects(:launch_task).with(expected_data).returns('{"id":"test-uuid"}')

    post '/launch/task', expected_data.to_json, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?
  end

  def test_post_launch_task_with_invalid_json_body
    post '/launch/task', 'not valid json{{{', 'CONTENT_TYPE' => 'application/json'
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('error'), 'Should return JSON error for invalid body'
    assert parsed['error']['message'].include?('Invalid JSON'), 'Error should mention invalid JSON'
  end

  def test_get_job_status_extracts_route_parameter
    Proxy::OpenBolt.expects(:get_status).with('abc-123').returns('{"status":"running"}')

    get '/job/abc-123/status'
    assert last_response.ok?
  end

  def test_get_job_result_extracts_route_parameter
    Proxy::OpenBolt.expects(:get_result).with('abc-123').returns('{"status":"success","value":{}}')

    get '/job/abc-123/result'
    assert last_response.ok?
  end

  def test_delete_job_artifacts_success
    job_id = 'aabbccdd-1122-3344-5566-778899aabbcc'
    artifact_file = File.join(@test_log_dir, "#{job_id}.json")
    File.write(artifact_file, '{}')

    delete "/job/#{job_id}/artifacts"
    assert last_response.ok?
    parsed = JSON.parse(last_response.body)
    assert_equal 'deleted', parsed['status']
    assert !File.exist?(artifact_file), 'Artifact file should be deleted'
  end

  def test_delete_job_artifacts_not_found
    delete '/job/aabbccdd-0000-0000-0000-000000000000/artifacts'
    parsed = JSON.parse(last_response.body)
    assert_equal 'not_found', parsed['status']
  end

  def test_delete_job_artifacts_rejects_invalid_id
    delete '/job/not-a-valid-hex-id!/artifacts'
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('error'), 'Should return an error for invalid job ID format'
  end

  def test_get_job_status_rejects_invalid_id
    get '/job/not-a-valid-hex-id!/status'
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('error'), 'Should return an error for invalid job ID format'
  end

  def test_get_job_result_rejects_invalid_id
    get '/job/not-a-valid-hex-id!/result'
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('error'), 'Should return an error for invalid job ID format'
  end

  def test_catch_errors_handles_openbolt_error
    Proxy::OpenBolt.stubs(:tasks).raises(
      Proxy::OpenBolt::Error.new(message: 'something failed')
    )

    get '/tasks'
    parsed = JSON.parse(last_response.body)
    assert parsed.key?('error'), 'Should return JSON error'
    assert_equal 'something failed', parsed['error']['message']
  end
end
