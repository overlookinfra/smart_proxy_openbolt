require 'test_helper'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/main'

class NormalizeValuesTest < SmartProxyOpenboltTestCase
  def test_strips_string_values
    assert_equal({ 'key' => 'val' }, Proxy::OpenBolt.normalize_values({ 'key' => ' val ' }))
  end

  def test_removes_empty_strings
    assert_equal({}, Proxy::OpenBolt.normalize_values({ 'key' => '' }))
  end

  def test_removes_whitespace_only_strings
    assert_equal({}, Proxy::OpenBolt.normalize_values({ 'key' => '   ' }))
  end

  def test_handles_nil_input
    assert_equal({}, Proxy::OpenBolt.normalize_values(nil))
  end

  def test_handles_non_hash_input
    assert_equal({}, Proxy::OpenBolt.normalize_values('not a hash'))
  end

  def test_strips_array_elements
    assert_equal({ 'key' => ['a', 'b'] }, Proxy::OpenBolt.normalize_values({ 'key' => [' a ', ' b '] }))
  end

  def test_removes_empty_arrays
    assert_equal({}, Proxy::OpenBolt.normalize_values({ 'key' => [] }))
  end

  def test_preserves_booleans
    result = Proxy::OpenBolt.normalize_values({ 'flag' => true })
    assert_equal({ 'flag' => true }, result)
  end

  def test_preserves_numbers
    result = Proxy::OpenBolt.normalize_values({ 'count' => 42 })
    assert_equal({ 'count' => 42 }, result)
  end
end

class ScrubTest < SmartProxyOpenboltTestCase
  def test_redacts_sensitive_values
    options = { 'password' => 'secret123', 'user' => 'admin' }
    text = 'connecting with password=secret123 user=admin'
    scrubbed = Proxy::OpenBolt.scrub(options, text)

    assert !scrubbed.include?('secret123'), 'Password should be redacted'
    assert scrubbed.include?('*****'), 'Password should be replaced with *****'
    assert scrubbed.include?('admin'), 'Non-sensitive values should not be redacted'
  end

  def test_does_not_redact_non_sensitive_values
    options = { 'user' => 'admin' }
    text = 'user=admin'
    scrubbed = Proxy::OpenBolt.scrub(options, text)

    assert scrubbed.include?('admin')
  end

  def test_handles_unknown_option_keys
    options = { 'unknown-key' => 'value' }
    text = 'some text with value in it'
    # Should not crash
    scrubbed = Proxy::OpenBolt.scrub(options, text)
    assert_equal text, scrubbed
  end

  def test_redacts_non_string_sensitive_values
    options = { 'password' => 123, 'sudo-password' => true }
    text = 'password=123 sudo-password=true'
    scrubbed = Proxy::OpenBolt.scrub(options, text)
    assert !scrubbed.include?('123'), 'Numeric password should be redacted'
    assert !scrubbed.include?('true'), 'Boolean password should be redacted'
  end

  def test_handles_nil_sensitive_value
    options = { 'password' => nil }
    text = 'password=nil'
    scrubbed = Proxy::OpenBolt.scrub(options, text)
    assert_equal text, scrubbed
  end

  def test_handles_empty_string_sensitive_value
    options = { 'password' => '' }
    text = 'password='
    scrubbed = Proxy::OpenBolt.scrub(options, text)
    assert_equal text, scrubbed
  end
end

class OpenboltOptionsTest < SmartProxyOpenboltTestCase
  def test_returns_sorted_hash
    options = Proxy::OpenBolt.openbolt_options
    keys = options.keys
    assert_equal keys.sort, keys
  end
end

class ValidateJobIdTest < SmartProxyOpenboltTestCase
  def test_accepts_standard_uuid
    assert_nothing_raised { Proxy::OpenBolt.validate_job_id!('aabbccdd-1122-3344-5566-778899aabbcc') }
  end

  def test_accepts_hex_only
    assert_nothing_raised { Proxy::OpenBolt.validate_job_id!('abc123def') }
  end

  def test_rejects_path_traversal
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.validate_job_id!('../../../etc/passwd') }
  end

  def test_rejects_shell_metacharacters
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.validate_job_id!('abc; rm -rf /') }
  end

  def test_rejects_empty_string
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.validate_job_id!('') }
  end

  def test_rejects_spaces
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.validate_job_id!('abc 123') }
  end

  def test_rejects_dots
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.validate_job_id!('abc.123') }
  end
end

class GetStatusAndResultTest < SmartProxyOpenboltTestCase
  def test_get_status_returns_invalid_for_unknown_job
    result = JSON.parse(Proxy::OpenBolt.get_status('00000000-0000-0000-0000-000000000000'))
    assert_equal 'invalid', result['status']
  end

  def test_get_result_raises_for_unknown_job
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.get_result('00000000-0000-0000-0000-000000000000')
    end
  end
end

class TasksTest < SmartProxyOpenboltTestCase
  def setup
    super
    # Reset cached tasks
    Proxy::OpenBolt.instance_variable_set(:@tasks, nil)
  end

  def test_tasks_returns_parsed_task_hash
    task_list_stdout = '{"tasks":[["my_module::my_task","A test task"]]}'
    task_show_stdout = '{"metadata":{"description":"A test task","parameters":{"name":{"type":"String"}}}}'

    Proxy::OpenBolt.expects(:openbolt).with { |cmd| cmd.include?('show') && !cmd.include?('my_module::my_task') }
                                      .returns([task_list_stdout, '', 0])
    Proxy::OpenBolt.expects(:openbolt).with { |cmd| cmd.include?('my_module::my_task') }
                                      .returns([task_show_stdout, '', 0])

    result = Proxy::OpenBolt.tasks
    assert result.key?('my_module::my_task')
    assert_equal 'A test task', result['my_module::my_task']['description']
    assert result['my_module::my_task']['parameters'].key?('name')
  end

  def test_tasks_caches_results
    task_list_stdout = '{"tasks":[["cached::task","Cached"]]}'
    task_show_stdout = '{"metadata":{"description":"Cached","parameters":{}}}'

    # First call requires exactly 2 openbolt invocations (list + show).
    # Second call should hit cache, so total remains 2.
    Proxy::OpenBolt.expects(:openbolt).twice
                   .returns([task_list_stdout, '', 0])
                   .then.returns([task_show_stdout, '', 0])

    Proxy::OpenBolt.tasks
    result = Proxy::OpenBolt.tasks
    assert result.key?('cached::task'), 'Cached result should still be accessible'
  end

  def test_tasks_reload_clears_cache
    task_list_stdout = '{"tasks":[["reload::task","Reloaded"]]}'
    task_show_stdout = '{"metadata":{"description":"Reloaded","parameters":{}}}'

    # 2 calls for initial load + 2 calls for reload = 4 total
    Proxy::OpenBolt.expects(:openbolt).times(4)
                   .returns([task_list_stdout, '', 0])
                   .then.returns([task_show_stdout, '', 0])
                   .then.returns([task_list_stdout, '', 0])
                   .then.returns([task_show_stdout, '', 0])

    Proxy::OpenBolt.tasks
    result = Proxy::OpenBolt.tasks(reload: true)
    assert result.key?('reload::task'), 'Reloaded result should be accessible'
  end

  def test_tasks_raises_cli_error_on_bolt_failure
    Proxy::OpenBolt.stubs(:openbolt).returns(['', 'bolt not found', 1])

    assert_raise(Proxy::OpenBolt::CliError) { Proxy::OpenBolt.tasks }
  end

  def test_tasks_raises_cli_error_on_per_task_fetch_failure
    task_list_stdout = '{"tasks":[["fail::task","Fails"]]}'

    Proxy::OpenBolt.expects(:openbolt).twice
                   .returns([task_list_stdout, '', 0])
                   .then.returns(['', 'task fetch failed', 1])

    assert_raise(Proxy::OpenBolt::CliError) { Proxy::OpenBolt.tasks }
  end

  def test_tasks_handles_signal_killed_bolt_on_task_list
    Proxy::OpenBolt.expects(:openbolt).once
                   .returns(['', "Process was killed by signal 9.\n", 137])

    error = assert_raise(Proxy::OpenBolt::CliError) { Proxy::OpenBolt.tasks }
    assert_equal 137, error.exitcode
  end

  def test_tasks_handles_signal_killed_bolt_on_per_task_fetch
    task_list_stdout = '{"tasks":[["killed::task","Killed"]]}'

    Proxy::OpenBolt.expects(:openbolt).twice
                   .returns([task_list_stdout, '', 0])
                   .then.returns(['', "Process was killed by signal 9.\n", 137])

    error = assert_raise(Proxy::OpenBolt::CliError) { Proxy::OpenBolt.tasks }
    assert_equal 137, error.exitcode
  end

  def test_tasks_raises_error_on_json_parse_failure
    Proxy::OpenBolt.stubs(:openbolt).returns(['not json at all', '', 0])

    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.tasks }
  end

  def test_tasks_raises_error_on_missing_tasks_key
    Proxy::OpenBolt.stubs(:openbolt).returns(['{"something_else": true}', '', 0])

    error = assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.tasks }
    assert_match(/expected 'tasks' to be an array/, error.message)
  end

  def test_tasks_raises_error_on_per_task_json_parse_failure
    task_list_stdout = '{"tasks":[["bad::task","Bad task"]]}'

    Proxy::OpenBolt.expects(:openbolt).twice
                   .returns([task_list_stdout, '', 0])
                   .then.returns(['not valid json', '', 0])

    error = assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.tasks }
    assert_match(/bolt task show bad::task/, error.message)
    assert_nil Proxy::OpenBolt.instance_variable_get(:@tasks)
  end

  def test_tasks_raises_error_on_nil_metadata
    task_list_stdout = '{"tasks":[["no_meta::task","No metadata"]]}'
    task_show_stdout = '{"something_else": "no metadata key"}'

    Proxy::OpenBolt.expects(:openbolt).twice
                   .returns([task_list_stdout, '', 0])
                   .then.returns([task_show_stdout, '', 0])

    error = assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.tasks }
    assert_match(/Invalid metadata/, error.message)
    assert_nil Proxy::OpenBolt.instance_variable_get(:@tasks)
  end
end

class LaunchTaskTest < SmartProxyOpenboltTestCase
  def setup
    super
    # Pre-populate tasks cache with a test task
    Proxy::OpenBolt.instance_variable_set(:@tasks, {
      'test::task' => {
        'description' => 'A test task',
        'parameters' => {
          'required_param' => { 'type' => 'String' },
          'optional_param' => { 'type' => 'Optional[String]' },
        },
      },
    })
  end

  # Stubs add_job to capture the job passed to it, launches the task with
  # sensible defaults, and returns the captured job for assertions.
  def capture_launched_job(options, name: 'test::task', parameters: { 'required_param' => 'val' }, targets: 'node1')
    captured = nil
    Proxy::OpenBolt.executor.stubs(:add_job).with { |job| captured = job }.returns('uuid')
    Proxy::OpenBolt.launch_task({
      'name' => name,
      'parameters' => parameters,
      'targets' => targets,
      'options' => options,
    })
    captured
  end

  def test_rejects_non_hash_data
    assert_raise(Proxy::OpenBolt::Error) { Proxy::OpenBolt.launch_task('not a hash') }
  end

  def test_rejects_missing_fields
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({ 'name' => 'test::task', 'targets' => 'node1' })
    end
  end

  def test_rejects_empty_name
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => '', 'parameters' => {}, 'targets' => 'node1', 'options' => {}
      })
    end
  end

  def test_rejects_unknown_task
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'nonexistent::task', 'parameters' => {}, 'targets' => 'node1', 'options' => {}
      })
    end
  end

  def test_rejects_missing_required_params
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => {}, 'targets' => 'node1', 'options' => {}
      })
    end
  end

  def test_rejects_extra_params
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task',
        'parameters' => { 'required_param' => 'val', 'unknown' => 'val' },
        'targets' => 'node1', 'options' => {}
      })
    end
  end

  def test_rejects_empty_targets
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => '', 'options' => {}
      })
    end
  end

  def test_successful_launch_with_array_targets
    Proxy::OpenBolt.executor.stubs(:add_job).returns('uuid')

    result = JSON.parse(Proxy::OpenBolt.launch_task({
      'name' => 'test::task',
      'parameters' => { 'required_param' => 'val' },
      'targets' => ['node1', 'node2'],
      'options' => { 'transport' => 'ssh' },
    }))

    assert_equal 'uuid', result['id']
  end

  def test_rejects_non_string_array_targets
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => [123, 'node1'], 'options' => {}
      })
    end
  end

  def test_rejects_blank_only_array_targets
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => ['  ', ''], 'options' => {}
      })
    end
  end

  def test_rejects_unknown_options
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => 'node1', 'options' => { 'made-up-option' => 'val' }
      })
    end
  end

  def test_rejects_invalid_boolean_option
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => 'node1', 'options' => { 'verbose' => 'maybe' }
      })
    end
  end

  def test_coerces_string_boolean_options
    job = capture_launched_job({ 'verbose' => 'true', 'noop' => 'false' })

    assert_equal true, job.options['verbose']
    assert_equal false, job.options['noop']
  end

  def test_rejects_invalid_enum_option
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task', 'parameters' => { 'required_param' => 'val' },
        'targets' => 'node1', 'options' => { 'transport' => 'carrier_pigeon' }
      })
    end
  end

  def test_successful_launch_returns_job_id
    Proxy::OpenBolt.executor.stubs(:add_job).returns('test-uuid-123')

    result = JSON.parse(Proxy::OpenBolt.launch_task({
      'name' => 'test::task',
      'parameters' => { 'required_param' => 'val' },
      'targets' => 'node1,node2',
      'options' => { 'transport' => 'ssh' },
    }))

    assert_equal 'test-uuid-123', result['id']
  end

  def test_applies_default_transport
    job = capture_launched_job({})

    assert_equal 'ssh', job.options['transport'], 'Default transport should be ssh'
  end

  def test_accepts_choria_transport_with_options
    job = capture_launched_job({
      'transport' => 'choria',
      'choria-task-agent' => 'bolt_tasks',
      'choria-config-file' => '/etc/choria/client.conf',
      'choria-collective' => 'mcollective',
      'choria-rpc-timeout' => '30',
    })

    assert_equal 'choria', job.options['transport']
    assert_equal 'bolt_tasks', job.options['choria-task-agent']
    assert_equal '/etc/choria/client.conf', job.options['choria-config-file']
    assert_equal 'mcollective', job.options['choria-collective']
    assert_equal '30', job.options['choria-rpc-timeout']
  end

  def test_rejects_invalid_choria_task_agent
    assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task',
        'parameters' => { 'required_param' => 'val' },
        'targets' => 'node1',
        'options' => { 'transport' => 'choria', 'choria-task-agent' => 'bogus' },
      })
    end
  end

  def test_accepts_shell_agent_for_choria_task_agent
    job = capture_launched_job({ 'transport' => 'choria', 'choria-task-agent' => 'shell' })

    assert_equal 'shell', job.options['choria-task-agent']
  end

  def test_rejects_blank_required_param
    error = assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'test::task',
        'parameters' => { 'required_param' => '   ' },
        'targets' => 'node1', 'options' => {}
      })
    end
    assert_match(/Missing required parameters/, error.message)
  end

  def test_handles_untyped_task_parameters
    Proxy::OpenBolt.instance_variable_set(:@tasks, {
      'untyped::task' => {
        'description' => 'Task with untyped param',
        'parameters' => {
          'name' => {},
        },
      },
    })
    Proxy::OpenBolt.executor.stubs(:add_job).returns('uuid')

    result = JSON.parse(Proxy::OpenBolt.launch_task({
      'name' => 'untyped::task',
      'parameters' => { 'name' => 'value' },
      'targets' => 'node1', 'options' => {}
    }))
    assert_equal 'uuid', result['id']
  end

  def test_rejects_missing_untyped_required_param
    Proxy::OpenBolt.instance_variable_set(:@tasks, {
      'untyped::task' => {
        'description' => 'Task with untyped param',
        'parameters' => {
          'name' => {},
        },
      },
    })

    error = assert_raise(Proxy::OpenBolt::Error) do
      Proxy::OpenBolt.launch_task({
        'name' => 'untyped::task',
        'parameters' => {},
        'targets' => 'node1', 'options' => {}
      })
    end
    assert_match(/Missing required parameters/, error.message)
  end

  def test_passes_non_string_option_value_through
    job = capture_launched_job({ 'user' => 123 })

    assert_equal 123, job.options['user']
  end

  def test_handles_null_options
    Proxy::OpenBolt.executor.stubs(:add_job).returns('uuid')

    result = JSON.parse(Proxy::OpenBolt.launch_task({
      'name' => 'test::task',
      'parameters' => { 'required_param' => 'val' },
      'targets' => 'node1',
      'options' => nil,
    }))

    assert_equal 'uuid', result['id']
  end

  def test_allows_omitting_parameter_with_default
    Proxy::OpenBolt.instance_variable_set(:@tasks, {
      'defaults::task' => {
        'description' => 'Task with default param',
        'parameters' => {
          'required_param' => { 'type' => 'String' },
          'has_default' => { 'type' => 'String', 'default' => 'foo' },
        },
      },
    })
    Proxy::OpenBolt.executor.stubs(:add_job).returns('uuid')

    result = JSON.parse(Proxy::OpenBolt.launch_task({
      'name' => 'defaults::task',
      'parameters' => { 'required_param' => 'val' },
      'targets' => 'node1', 'options' => {}
    }))

    assert_equal 'uuid', result['id']
  end
end

class OpenboltEnvTest < SmartProxyOpenboltTestCase
  def test_openbolt_passes_base_env_only
    status = stub(exitstatus: 0)
    Open3.expects(:capture3).with(
      { 'BOLT_GEM' => 'true', 'BOLT_DISABLE_ANALYTICS' => 'true' },
      'echo', 'test'
    ).returns(['', '', status])

    Proxy::OpenBolt.openbolt(['echo', 'test'])
  end
end

class ChoriaDefaultsTest < SmartProxyOpenboltTestCase
  def setup
    super
    Proxy::OpenBolt.instance_variable_set(:@tasks, {
      'test::task' => {
        'description' => 'A test task',
        'parameters' => {
          'required_param' => { 'type' => 'String' },
        },
      },
    })

    @cert_dir = Dir.mktmpdir('choria-test-certs-')
    @cert_path = File.join(@cert_dir, 'primary.example.com.pem')
    @key_path = File.join(@cert_dir, 'primary.example.com.key')
    @ca_path = File.join(@cert_dir, 'ca.pem')

    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('CN=primary.example.com')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    File.write(@cert_path, cert.to_pem)
    File.write(@key_path, key.to_pem)
    File.write(@ca_path, cert.to_pem)
  end

  def teardown
    super
    FileUtils.rm_rf(@cert_dir)
  end

  def stub_proxy_ssl
    Proxy::SETTINGS.stubs(:ssl_certificate).returns(@cert_path)
    Proxy::SETTINGS.stubs(:ssl_private_key).returns(@key_path)
    Proxy::SETTINGS.stubs(:ssl_ca_file).returns(@ca_path)
  end

  def stub_proxy_no_ssl
    Proxy::SETTINGS.stubs(:ssl_certificate).returns(nil)
    Proxy::SETTINGS.stubs(:ssl_private_key).returns(nil)
    Proxy::SETTINGS.stubs(:ssl_ca_file).returns(nil)
  end

  def capture_launched_job(options, name: 'test::task', parameters: { 'required_param' => 'val' }, targets: 'node1')
    captured = nil
    Proxy::OpenBolt.executor.stubs(:add_job).with { |job| captured = job }.returns('uuid')
    Proxy::OpenBolt.launch_task({
      'name' => name, 'parameters' => parameters, 'targets' => targets, 'options' => options,
    })
    captured
  end

  def test_defaults_choria_config_file_to_shipped_config
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'choria' })
    config_path = job.options['choria-config-file']
    assert config_path, 'Expected choria-config-file to be set'
    assert File.readable?(config_path), "Shipped config not readable at #{config_path}"
    assert config_path.end_with?('choria-client.conf')
  end

  def test_defaults_choria_ssl_from_proxy_settings
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'choria' })
    assert_equal @cert_path, job.options['choria-ssl-cert']
    assert_equal @key_path, job.options['choria-ssl-key']
    assert_equal @ca_path, job.options['choria-ssl-ca']
  end

  def test_derives_certname_from_cert_cn
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'choria' })
    assert_equal 'primary.example.com', job.options['choria-mcollective-certname']
  end

  def test_does_not_default_ssl_when_user_provides_config_file
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'choria', 'choria-config-file' => '/custom/choriarc' })
    assert_equal '/custom/choriarc', job.options['choria-config-file']
    assert_nil job.options['choria-ssl-cert']
    assert_nil job.options['choria-ssl-key']
    assert_nil job.options['choria-ssl-ca']
  end

  def test_does_not_derive_certname_when_user_provides_config_file
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'choria', 'choria-config-file' => '/custom/choriarc' })
    assert_nil job.options['choria-mcollective-certname']
  end

  def test_preserves_explicit_choria_ssl_options
    stub_proxy_ssl
    job = capture_launched_job({
      'transport' => 'choria',
      'choria-ssl-cert' => '/custom/cert.pem',
      'choria-ssl-key' => '/custom/key.pem',
      'choria-ssl-ca' => '/custom/ca.pem',
    })
    assert_equal '/custom/cert.pem', job.options['choria-ssl-cert']
    assert_equal '/custom/key.pem', job.options['choria-ssl-key']
    assert_equal '/custom/ca.pem', job.options['choria-ssl-ca']
  end

  def test_preserves_explicit_certname
    stub_proxy_ssl
    job = capture_launched_job({
      'transport' => 'choria',
      'choria-mcollective-certname' => 'custom-identity',
    })
    assert_equal 'custom-identity', job.options['choria-mcollective-certname']
  end

  def test_does_not_add_choria_defaults_for_ssh
    stub_proxy_ssl
    job = capture_launched_job({ 'transport' => 'ssh', 'user' => 'admin' })
    assert_nil job.options['choria-config-file']
    assert_nil job.options['choria-ssl-cert']
    assert_nil job.options['choria-mcollective-certname']
  end

  def test_does_not_default_ssl_when_proxy_has_no_ssl
    stub_proxy_no_ssl
    job = capture_launched_job({ 'transport' => 'choria', 'choria-brokers' => 'broker:4222' })
    assert_nil job.options['choria-ssl-cert']
    assert_nil job.options['choria-ssl-key']
    assert_nil job.options['choria-ssl-ca']
    assert_nil job.options['choria-mcollective-certname']
  end
end
