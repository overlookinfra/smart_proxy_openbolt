require 'json'
require 'sinatra'
require 'smart_proxy_openbolt/plugin'
require 'smart_proxy_openbolt/main'
require 'smart_proxy_openbolt/error'

module Proxy::OpenBolt

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
    Thread.new do
      Proxy::OpenBolt.tasks
    rescue => error
      Proxy::OpenBolt.logger.error("Task prefetch failed (#{error.class}): #{error.message}")
      Proxy::OpenBolt.logger.debug(error.backtrace.join("\n")) if error.backtrace
    end

    get '/tasks' do
      catch_errors { Proxy::OpenBolt.tasks.to_json }
    end

    get '/tasks/reload' do
      catch_errors { Proxy::OpenBolt.tasks(reload: true).to_json }
    end

    get '/tasks/options' do
      catch_errors { Proxy::OpenBolt.openbolt_options.to_json}
    end

    post '/launch/task' do
      catch_errors do
        begin
          data = JSON.parse(request.body.read)
        rescue JSON::ParserError => parse_error
          raise Error.new(message: "Invalid JSON in request body: #{parse_error.message}")
        end
        Proxy::OpenBolt.launch_task(data)
      end
    end

    get '/job/:id/status' do |id|
      catch_errors { Proxy::OpenBolt.get_status(id) }
    end

    get '/job/:id/result' do |id|
      catch_errors { Proxy::OpenBolt.get_result(id) }
    end

    delete '/job/:id/artifacts' do |id|
      catch_errors { Proxy::OpenBolt.delete_artifacts(id) }
    end

    private

    def catch_errors
      yield
    rescue Error => error
      error.to_json
    end
  end
end
