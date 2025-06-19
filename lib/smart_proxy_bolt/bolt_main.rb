module Proxy::Bolt
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self

    def say_hello
      Proxy::Bolt::Plugin.settings.hello_greeting
    end

  end
end
