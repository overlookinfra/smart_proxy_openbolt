require 'fileutils'

module Proxy::OpenBolt
  class NotFound < RuntimeError; end

  class LogPathValidator < ::Proxy::PluginValidators::Base
    def validate!(settings)
      logdir = settings[:log_dir]
      unless Dir.exist?(logdir)
        FileUtils.mkdir_p(logdir)
        FileUtils.chown('foreman-proxy','foreman-proxy',logdir)
        FileUtils.chmod(0750, logdir)
      end
      raise ::Proxy::Error::ConfigurationError("Could not create log dir at #{logdir}") unless Dir.exist?(logdir)
    end
  end

  class Plugin < ::Proxy::Plugin
    plugin :openbolt, Proxy::OpenBolt::VERSION

    expose_setting :enabled

    capability :tasks

    # TODO: Validate this is a valid path
    default_settings(
      environment_path: '/etc/puppetlabs/code/environments/production',
      workers: 20,
      concurrency: 100,
      connect_timeout: 30,
      log_dir: '/var/log/foreman-proxy/openbolt'
    )

    load_validators :log_path_validator => Proxy::OpenBolt::LogPathValidator
    validate_readable :environment_path
    validate :log_dir, :log_path_validator => true

    https_rackup_path File.expand_path('http_config.ru', File.expand_path('../', __FILE__))
  end
end
