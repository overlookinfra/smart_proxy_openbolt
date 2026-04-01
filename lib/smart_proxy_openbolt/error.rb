module Proxy::OpenBolt
  class Error < StandardError
    attr_reader :details

    def initialize(message:, **details)
      @details = details
      super(message)
    end

    def to_json(*args)
      result = { message: message }
      details.each do |key, val|
        if key == :exception && val.is_a?(Exception)
          result[:exception] = {
            class:     val.class.to_s,
            message:   val.message,
            backtrace: val.backtrace,
          }
        else
          result[key] = val unless val.nil?
        end
      end
      { error: result }.to_json(*args)
    end
  end

  class CliError < Error
    def exitcode = details[:exitcode]
    def stdout = details[:stdout]
    def stderr = details[:stderr]
    def command = details[:command]
  end
end
