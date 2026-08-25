# frozen_string_literal: true

require 'singleton'

require 'recorder/sidekiq'

module Recorder
  # Global configuration options
  class Config
    include Singleton
    attr_accessor :sidekiq_options
    attr_reader :ignore, :async

    def initialize
      reset
    end

    def ignore=(value)
      @ignore = Array.wrap(value).map(&:to_sym)
    end

    # Guarded like the per-model `async:` option. This path is reachable without
    # any model declaring anything, so it needs the same fail-fast treatment.
    def async=(value)
      Recorder.assert_async_available!(value, '`Recorder.config.async` is set to true')

      @async = !!value
    end

    # Indicates whether Recorder is on or off. Default: true.
    def enabled
      @mutex.synchronize { !!@enabled }
    end

    def enabled=(enable)
      @mutex.synchronize { @enabled = enable }
    end

    def reset
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
  end
end
