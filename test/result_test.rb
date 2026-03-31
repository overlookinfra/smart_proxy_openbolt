require 'test_helper'
require 'smart_proxy_openbolt/result'

class ResultTest < Test::Unit::TestCase
  def test_exitcode_zero_with_valid_json
    result = Proxy::OpenBolt::Result.new('bolt task run foo', '{"items":[]}', 'log output', 0)

    assert_equal :success, result.status
    assert_equal({ 'items' => [] }, result.value)
    assert_equal 'log output', result.log
    assert_equal 'bolt task run foo', result.command
  end

  def test_exitcode_zero_with_invalid_json
    result = Proxy::OpenBolt::Result.new('cmd', 'not json', 'stderr', 0)

    assert_equal :exception, result.status
    assert result.message.include?('unexpected token'), "Expected JSON parse error message, got: #{result.message}"
  end

  def test_exitcode_one_with_json_stdout
    stdout = '{"items":[{"target":"node1","status":"failure"}]}'
    result = Proxy::OpenBolt::Result.new('cmd', stdout, 'log', 1)

    assert_equal :failure, result.status
    assert_equal({ 'items' => [{ 'target' => 'node1', 'status' => 'failure' }] }, result.value)
    assert_equal 'log', result.log
  end

  def test_exitcode_one_with_non_json_stdout
    result = Proxy::OpenBolt::Result.new('cmd', 'Task not found: foo', 'stderr', 1)

    assert_equal :failure, result.status
    assert_equal 'Task not found: foo', result.value
    assert_equal 'stderr', result.log
  end

  def test_exitcode_greater_than_one
    result = Proxy::OpenBolt::Result.new('cmd', 'some output', 'some error', 2)

    assert_equal :exception, result.status
    assert result.message.include?('exited with code 2'), "Expected exit code in message, got: #{result.message}"
    assert result.value.include?('some error'), "Expected stderr in value"
    assert result.value.include?('some output'), "Expected stdout in value"
  end

  def test_schema_version
    # Different exit codes run through different code paths. Only
    # one schema version exists right now. Just make sure they
    # don't deviate.
    [0, 1, 2].each do |exitcode|
      stdout = exitcode <= 1 ? '{"items":[]}' : 'output'
      result = Proxy::OpenBolt::Result.new('cmd', stdout, 'err', exitcode)
      assert_equal 1, result.schema, "Schema version should be 1 for exitcode #{exitcode}"
    end
  end

  def test_to_json_produces_valid_json
    result = Proxy::OpenBolt::Result.new('cmd', '{"items":[]}', 'log', 0)
    parsed = JSON.parse(result.to_json)

    assert parsed.key?('command')
    assert parsed.key?('status')
    assert parsed.key?('value')
    assert parsed.key?('log')
    assert parsed.key?('schema')
  end

  def test_command_is_preserved
    result = Proxy::OpenBolt::Result.new('bolt task run my::task --targets node1', '{}', '', 0)
    assert_equal 'bolt task run my::task --targets node1', result.command
  end
end
