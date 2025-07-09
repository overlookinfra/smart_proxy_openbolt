require 'sinatra'
require 'smart_proxy_example/example'
require 'smart_proxy_example/example_main'

module Proxy::Example

  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    get '/hello' do
      Proxy::Example.say_hello
    end
  end
end
