require 'test/unit'
require 'mocha/test_unit'
require 'rack/test'
require 'json'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

require 'smart_proxy_for_testing'

# Create logs directory in a temp dir to avoid polluting the project tree
logdir = File.join(Dir.tmpdir, 'openbolt-test-logs')
FileUtils.mkdir_p(logdir)

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
end
