# frozen_string_literal: true

require 'singleton'

module Recorder
  # Global configuration options
  class Config
    include Singleton
    attr_accessor :sidekiq_options
    attr_reader :ignore, :async

    def initialize
      # Variables which affect all threads, whose access is synchronized.
      @mutex = Mutex.new
      @enabled = true

      @sidekiq_options = {
        queue: 'recorder',
        retry: 10,
        backtrace: true
      }

      @ignore = []
      @async = false
    end

    def ignore=(value)
      @ignore = Array.wrap(value).map(&:to_sym)
    end

    def async=(value)
      @async = !!value
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
