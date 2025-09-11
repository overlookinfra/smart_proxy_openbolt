require 'json'

module Proxy::OpenBolt
  class Result

    attr_reader :command, :status, :value, :log, :message, :schema

    # Result from the OpenBolt CLI with --format json looks like:
    #
    # { "items": [
    #     {
    #       "target": "certname1",
    #       "action": "task",
    #       "object": "task::name",
    #       "status": "success",
    #       "value": <whatever the task returns>
    #     },
    #     {
    #       "target": "certname2",
    #       ...
    #     }
    #   ],
    #   "target_count": 2,
    #   "elapsed_time": 3
    # }

    # This class will take the raw stdout, stderr, status.exitcode objects from a
    # OpenBolt CLI invocation, and parse them accordingly. This should only be
    # used with the --format json flag passed to the OpenBolt CLI, as that changes
    # what data gets put on stdout and stderr.
    #
    # The "exception" parameter is to be able to handle an unexpected exception,
    # and should generally not be used except where it is right now.
    def initialize(command, stdout, stderr, exitcode)
      @schema = 1
      @command = command
      if exitcode > 1
        @message = "Command unexpectedly exited with code #{exitcode}"
        @status = :exception
        @value = "stderr:\n#{stderr}\nstdout:\n#{stdout}"
      else
        if exitcode == 1 && !stdout.start_with?('{')
          @value = stdout
          @status = :failure
          @log = stderr
        else
          begin
            @value = JSON.parse(stdout)
            @status = exitcode == 0 ? :success : :failure
            @log = stderr
          rescue JSON::ParserError => e
            @status = :exception
            @message = e.message
            @value = e.inspect
            @log = stderr
          end
        end
      end
    end

    def to_json
      {
        'command': @command,
        'status': @status,
        'value': @value,
        'log': @log,
        'message': @message,
        'schema': @schema,
      }.to_json
    end
  end
end
