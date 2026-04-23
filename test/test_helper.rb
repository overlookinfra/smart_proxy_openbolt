require 'test/unit'
require 'mocha/test_unit'
require 'rack/test'
require 'json'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

# smart_proxy_for_testing hardcodes log_file to ./logs/test.log. If that
# directory doesn't exist the logger falls back to STDOUT, flooding test
# output with DEBUG/ERROR lines that mask real failures. Create it before
# loading the test harness so logs go to a file instead.
SMART_PROXY_LOG_DIR = File.join(File.dirname(__FILE__), '..', 'logs')
FileUtils.mkdir_p(SMART_PROXY_LOG_DIR)

require 'smart_proxy_for_testing'

at_exit { FileUtils.rm_rf(SMART_PROXY_LOG_DIR) }

# Base test class with temp log_dir management for tests that need disk I/O
class SmartProxyOpenboltTestCase < Test::Unit::TestCase
  def setup
    @test_log_dir = Dir.mktmpdir('openbolt-test-')
    Proxy::OpenBolt::Plugin.load_test_settings(
      environment_path: '/tmp/test-environments',
      workers: 2,
      concurrency: 10,
      connect_timeout: 5,
      log_dir: @test_log_dir
    )
  end

  def teardown
    FileUtils.rm_rf(@test_log_dir) if @test_log_dir && Dir.exist?(@test_log_dir)
  end

  def capture_launched_job(options, name: 'test::task', parameters: { 'required_param' => 'val' }, targets: 'node1')
    captured = nil
    Proxy::OpenBolt.executor.stubs(:add_job).with { |job| captured = job }.returns('uuid')
    Proxy::OpenBolt.launch_task({
      'name' => name, 'parameters' => parameters, 'targets' => targets, 'options' => options,
    })
    captured
  end
end
