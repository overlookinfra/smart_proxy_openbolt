module Proxy::OpenBolt
  class Error < StandardError
    def initialize(**fields)
      fields.each { |key, val| instance_variable_set("@#{key}", val) }
      super(fields[:message])
    end

    def to_json
      details = {}
      instance_variables.each do |var|
        name = var.to_s.delete("@").to_sym
        val = instance_variable_get(var)

        next if val.nil?

        if name == :exception && val.is_a?(Exception)
          details[:exception] = {
            class:     val.class.to_s,
            message:   val.message,
            backtrace: val.backtrace
          }
        else
          details[name] = val
        end
      end
      { error: details }.to_json
    end
  end

  class CliError < Error
    attr_accessor :exitcode, :stdout, :stderr, :command

    def initialize(message:, exitcode:, stdout:, stderr:, command:)
      super(
        message:  message,
        exitcode: exitcode,
        stdout:   stdout,
        stderr:   stderr,
        command:  command,
      )
    end
  end
end
