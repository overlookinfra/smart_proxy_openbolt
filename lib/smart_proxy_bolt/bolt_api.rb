require 'sinatra'
require 'smart_proxy_bolt/bolt'
require 'smart_proxy_bolt/bolt_main'
require 'smart_proxy_bolt/error'
require 'json'

module Proxy::Bolt

  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    # Require authentication
    # These require foreman-proxy to be able to read Puppet's certs/CA, which
    # by default are owned by puppet:puppet. Need to have installation figure out
    # the best way to open them to foreman-proxy if we want to use this, I think.
    #authorize_with_trusted_hosts
    #authorize_with_ssl_client

    # Call reload_tasks at class load so the first call to /tasks
    # is potentially faster (if called after this finishes). Do it
    # async so we don't block. The reload_tasks function uses a mutex
    # so it will be safe to call /tasks before it completes.
    Thread.new { Proxy::Bolt.tasks }

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

    private

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
  end
end
