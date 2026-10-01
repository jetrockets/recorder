# frozen_string_literal: true

require 'singleton'

module Recorder
  # Global configuration options
  class Config
    include Singleton
    attr_reader :ignore

    def initialize
      reset
    end

    def ignore=(value)
      @ignore = Array.wrap(value).map(&:to_sym)
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
      @ignore = []
    end
  end
end
