# frozen_string_literal: true

require 'recorder/config'
require 'recorder/version'

require 'recorder/changeset'
require 'recorder/store'
require 'recorder/manager'
require 'recorder/options'
require 'recorder/observer'

require 'recorder/rails/controller_concern'

module Recorder
  # Columns Recorder writes itself, which `Recorder.info` cannot set.
  RESERVED_INFO_KEYS = %i[id item_type item_id event data created_at].freeze
  private_constant :RESERVED_INFO_KEYS

  class << self
    # Switches Recorder on or off for the whole process, every thread
    # included. To switch it off for the current request or thread only, use
    # `Recorder::Manager#recorder_disabled!`.
    # @api public
    def enabled=(value)
      Recorder.config.enabled = value
    end

    # Returns `true` if Recorder is on for the process, `false` otherwise.
    # Recorder is enabled by default. `recorder_disabled!` can still have
    # recording off for the current request or thread.
    # @api public
    def enabled?
      !!Recorder.config.enabled
    end

    # Returns `true` if a change is recorded now: Recorder is on for the
    # process and not switched off for the current request or thread.
    # @api private
    def recording?
      enabled? && store.recorder_enabled?
    end

    # Sets Recorder information from the controller. Keys are stored as
    # symbols, so a string key replaces the symbol one rather than sitting
    # beside it.
    # @raise [ArgumentError] if the hash sets a column Recorder writes itself
    # @api public
    def info=(hash)
      hash = hash.symbolize_keys
      reserved = hash.keys & RESERVED_INFO_KEYS

      if reserved.any?
        raise ArgumentError, "Recorder.info cannot set columns Recorder writes itself: #{reserved.join(", ")}. " \
                             'To date a revision, set action_date.'
      end

      store.params.merge!(hash)
    end

    # Sets Recorder meta information.
    # @api public
    def meta=(hash)
      store.params[:meta] = hash
    end

    # Returns Recorder's configuration object.
    # @api private
    def config
      @config ||= Recorder::Config.instance
      yield @config if block_given?
      @config
    end

    # Thread-safe hash to hold Recorder's data.
    # @api private
    def store
      @store ||= Recorder::Store.new
    end

    # The absolute name of the revision class, from
    # `Recorder.config.revision_class`, without looking the constant up.
    # @api private
    def revision_class_name
      name = config.revision_class
      name ? "::#{name.delete_prefix("::")}" : '::Recorder::Revision'
    end

    # The revision class, looked up on every call and never kept, so a class
    # that was reloaded is the one returned.
    # @raise [ArgumentError] if `Recorder.config.revision_class` names
    #   something other than `Recorder::Revision` or a subclass of it, or a
    #   subclass Active Record would treat as single-table inheritance
    # @api private
    def revision_class
      return Recorder::Revision unless config.revision_class

      klass = revision_class_name.safe_constantize
      unless klass.is_a?(Class) && klass <= Recorder::Revision
        raise ArgumentError, 'Recorder.config.revision_class must name Recorder::Revision or a subclass of it, ' \
                             "got #{config.revision_class.inspect}"
      end
      unless klass.descends_from_active_record?
        raise ArgumentError, "#{klass.name} would store its name in the `#{klass.inheritance_column}` column of " \
                             "#{klass.table_name} and filter by it. Set `self.inheritance_column = nil` in #{klass.name}."
      end

      klass
    end

    # Returns version of Recorder as +String+
    def version
      VERSION
    end
  end
end

require 'recorder/revision'
