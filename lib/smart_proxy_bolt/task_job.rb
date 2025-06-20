require 'smart_proxy_bolt/job'

module Proxy::Bolt
  class TaskJob < Job
    attr_reader :targets

    def initialize(name, parameters, targets)
      super(name, parameters)
      @targets = targets
    end

    def execute
      sleep 10
      if Random.rand(10) < 2
        raise Proxy::Bolt::Error(message: "uh oh")
      else
        return "I ran #{@name} with parameters #{@parameters} on #{@targets}"
      end
    end
  end
end
