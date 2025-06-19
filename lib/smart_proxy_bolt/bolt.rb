module Proxy::Bolt
  class NotFound < RuntimeError; end

  class Plugin < ::Proxy::Plugin
    plugin 'bolt', Proxy::Bolt::VERSION

    default_settings :hello_greeting => 'O hai!'

    http_rackup_path File.expand_path('bolt_http_config.ru', File.expand_path('../', __FILE__))
    https_rackup_path File.expand_path('bolt_http_config.ru', File.expand_path('../', __FILE__))
  end
end
