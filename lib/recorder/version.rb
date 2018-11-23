module Recorder
  # :nodoc:
  module VERSION
    MAJOR = 0
    MINOR = 2
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join(".").freeze

    def self.to_s
      STRING
    end
  end
end
