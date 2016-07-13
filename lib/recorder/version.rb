module Recorder
  # :nodoc:
  module VERSION
    MAJOR = 0
    MINOR = 1
    PATCH = 14
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join(".").freeze

    def self.to_s
      STRING
    end
  end
end
