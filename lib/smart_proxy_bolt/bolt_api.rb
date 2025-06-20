require 'sinatra'
require 'smart_proxy_bolt/bolt'
require 'smart_proxy_bolt/bolt_main'
require 'smart_proxy_bolt/error'
require 'json'

module Proxy::Bolt

  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    def run(&block)
      begin
        yield
      rescue Proxy::Bolt::Error => e
        e.to_json
      rescue Exception => e
        raise e
        #Proxy::Bolt::Error.new(message: "Unhandled exception", exception: e).to_json
      end
    end

    get '/tasks' do
      run { Proxy::Bolt.tasks.to_json }
    end

    get '/tasks/reload' do
      run { Proxy::Bolt.tasks(reload: true).to_json }
    end

    post '/run/task' do
      run do
        data = JSON.parse(request.body.read)
        Proxy::Bolt.run_task(data)
      end
    end

    get '/job/:id/status' do |id|
      run { Proxy::Bolt.get_status(id) }
    end

    get '/job/:id/result' do |id|
      run { Proxy::Bolt.get_result(id) }
    end

    get '/job/:id/error' do |id|
      run { Proxy::Bolt.get_error(id) }
    end
  end
end
