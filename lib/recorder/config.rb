# frozen_string_literal: true

require 'singleton'

module Recorder
  # Global configuration options
  class Config
    include Singleton
    attr_reader :ignore, :revision_class

    def initialize
      reset
    end

    def ignore=(value)
      @ignore = Array.wrap(value).map(&:to_sym)
    end

    # The name of the class revisions are written and read through, a subclass
    # of `Recorder::Revision`, or nil for `Recorder::Revision` itself. Kept as
    # a name and looked up when used, so a reloaded class is picked up.
    # @raise [ArgumentError] for anything but a class name String or nil
    def revision_class=(name)
      unless name.nil? || (name.is_a?(String) && name.present?)
        raise ArgumentError, "`revision_class` expects a class name as a String, or nil, got #{name.inspect}. " \
                             'Pass the name, not the class, so the class can be reloaded.'
      end

      @revision_class = name&.dup&.freeze
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
      @revision_class = nil
    end
  end
end
