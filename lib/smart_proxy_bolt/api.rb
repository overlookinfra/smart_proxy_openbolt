require 'json'
require 'sinatra'
require 'smart_proxy_bolt/plugin'
require 'smart_proxy_bolt/main'
require 'smart_proxy_bolt/error'

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
      catch_errors { Proxy::Bolt.tasks.to_json }
    end

    get '/tasks/reload' do
      catch_errors { Proxy::Bolt.tasks(reload: true).to_json }
    end

    get '/tasks/options' do
      catch_errors { Proxy::Bolt.bolt_options.to_json}
    end

    post '/run/task' do
      catch_errors do
        data = JSON.parse(request.body.read)
        Proxy::Bolt.run_task(data)
      end
    end

    get '/job/:id/status' do |id|
      catch_errors { Proxy::Bolt.get_status(id) }
    end

    get '/job/:id/result' do |id|
      catch_errors { Proxy::Bolt.get_result(id) }
    end

    delete '/job/:id/artifacts' do |id|
      catch_errors do
        # Validate the job ID format to prevent directory traversal
        unless id =~ /\A[a-f0-9\-]+\z/i
          raise Proxy::Bolt::Error.new(message: "Invalid job ID format")
        end

        file_path = File.join(Proxy::Bolt::Plugin.settings.log_dir, "#{id}.json")

        if File.exist?(file_path)
          real_path = File.realpath(file_path)
          expected_dir = File.realpath(Proxy::Bolt::Plugin.settings.log_dir)
          raise Proxy::Bolt::Error.new(message: "Invalid file path") unless real_path.start_with?(expected_dir)

          File.delete(file_path)
          logger.info("Deleted artifacts for job #{id}")
          { status: 'deleted', job_id: id, path: file_path }.to_json
        else
          logger.warning("Artifacts not found for job #{id}")
          { status: 'not_found', job_id: id }.to_json
        end
      end
    end

    private

    def catch_errors(&block)
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
