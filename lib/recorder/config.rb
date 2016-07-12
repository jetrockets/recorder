require 'singleton'

module Recorder
  # Global configuration options
  class Config
    include Singleton
    attr_accessor :sidekiq_options

    def initialize
      # Variables which affect all threads, whose access is synchronized.
      @mutex = Mutex.new
      @enabled = true

      @sidekiq_options = {
        :queue => 'recorder',
        :retry => 10,
        :backtrace => true
      }
    end

    # Indicates whether Recorder is on or off. Default: true.
    def enabled
      @mutex.synchronize { !!@enabled }
    end

    def enabled=(enable)
      @mutex.synchronize { @enabled = enable }
    end
  end
end
