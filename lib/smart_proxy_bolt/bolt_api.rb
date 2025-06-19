require 'sinatra'
require 'smart_proxy_bolt/bolt'
require 'smart_proxy_bolt/bolt_main'

module Proxy::Bolt

  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    get '/hello' do
      Proxy::Bolt.say_hello
    end
  end
end
