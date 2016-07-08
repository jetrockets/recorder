module Recorder
  # :nodoc:
  module VERSION
    MAJOR = 0
    MINOR = 1
    TINY = 4
    PRE = nil

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join(".").freeze

    def self.to_s
      STRING
    end
  end
end
