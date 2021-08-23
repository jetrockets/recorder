module Recorder
  # :nodoc:
  module VERSION
    MAJOR = 1
    MINOR = 0
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join(".").freeze

    def self.to_s
      STRING
    end
  end
end
