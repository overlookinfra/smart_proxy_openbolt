require 'test_helper'
require 'smart_proxy_openbolt/error'

class ErrorTest < SmartProxyOpenboltTestCase
  def test_message_accessible
    error = Proxy::OpenBolt::Error.new(message: 'something broke')
    assert_equal 'something broke', error.message
  end

  def test_to_json_with_message_only
    error = Proxy::OpenBolt::Error.new(message: 'test error')
    parsed = JSON.parse(error.to_json)

    assert_equal 'test error', parsed['error']['message']
    assert_equal 1, parsed['error'].size, 'Should only contain message when no details given'
  end

  def test_to_json_with_additional_details
    error = Proxy::OpenBolt::Error.new(message: 'bad input', command: 'bolt task run foo')
    parsed = JSON.parse(error.to_json)

    assert_equal 'bad input', parsed['error']['message']
    assert_equal 'bolt task run foo', parsed['error']['command']
  end

  def test_to_json_excludes_nil_values
    error = Proxy::OpenBolt::Error.new(message: 'test', extra: nil)
    parsed = JSON.parse(error.to_json)

    assert !parsed['error'].key?('extra'), 'nil values should be excluded from JSON'
  end

  def test_to_json_serializes_exception
    begin
      raise RuntimeError, 'inner error'
    rescue RuntimeError => inner
      error = Proxy::OpenBolt::Error.new(message: 'wrapper', exception: inner)
      parsed = JSON.parse(error.to_json)

      assert_equal 'RuntimeError', parsed['error']['exception']['class']
      assert_equal 'inner error', parsed['error']['exception']['message']
      assert parsed['error']['exception']['backtrace'].is_a?(Array)
    end
  end

  def test_details_hash_accessible
    error = Proxy::OpenBolt::Error.new(message: 'test', foo: 'bar', count: 42)
    assert_equal({ foo: 'bar', count: 42 }, error.details)
  end

  def test_inherits_from_standard_error
    error = Proxy::OpenBolt::Error.new(message: 'test')
    assert error.is_a?(StandardError), 'Error should be a StandardError'
  end
end

class CliErrorTest < SmartProxyOpenboltTestCase
  def test_inherits_from_error
    error = Proxy::OpenBolt::CliError.new(
      message: 'failed', exitcode: 1, stdout: 'out', stderr: 'err', command: 'bolt task show'
    )
    assert error.is_a?(Proxy::OpenBolt::Error)
  end

  def test_to_json_includes_all_fields
    error = Proxy::OpenBolt::CliError.new(
      message: 'failed', exitcode: 2, stdout: 'output', stderr: 'error text', command: 'bolt task run foo'
    )
    parsed = JSON.parse(error.to_json)

    assert_equal 'failed', parsed['error']['message']
    assert_equal 2, parsed['error']['exitcode']
    assert_equal 'output', parsed['error']['stdout']
    assert_equal 'error text', parsed['error']['stderr']
    assert_equal 'bolt task run foo', parsed['error']['command']
  end

  def test_convenience_accessors
    error = Proxy::OpenBolt::CliError.new(
      message: 'failed', exitcode: 1, stdout: 'out', stderr: 'err', command: 'cmd'
    )
    assert_equal 1, error.exitcode
    assert_equal 'out', error.stdout
    assert_equal 'err', error.stderr
    assert_equal 'cmd', error.command
  end
end
