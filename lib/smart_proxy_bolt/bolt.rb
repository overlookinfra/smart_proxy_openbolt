module Proxy::Bolt
  class NotFound < RuntimeError; end

  class Plugin < ::Proxy::Plugin
    plugin 'bolt', Proxy::Bolt::VERSION

    # TODO: Validate this is a valid path
    default_settings environment_path: '/etc/puppetlabs/code/environments/production', workers: 10, concurrency: 100, connect_timeout: 30

    http_rackup_path File.expand_path('bolt_http_config.ru', File.expand_path('../', __FILE__))
    https_rackup_path File.expand_path('bolt_http_config.ru', File.expand_path('../', __FILE__))
  end
end
