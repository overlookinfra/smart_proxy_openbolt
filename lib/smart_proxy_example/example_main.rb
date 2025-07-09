module Proxy::Example
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self

    def say_hello
      Proxy::Example::Plugin.settings.hello_greeting
    end

  end
end
