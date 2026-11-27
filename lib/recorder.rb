# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'

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

    # Returns a frozen copy of the current Recorder information: every key
    # set through `info=` and `meta=`, or an empty Hash.
    # @api public
    def info
      params = store.params.dup
      params[:meta] = current_meta if params.key?(:meta)
      frozen_copy(params)
    end

    # Returns a frozen copy of the current meta, or `nil`.
    # @api public
    def meta
      frozen_copy(current_meta)
    end

    # Returns a frozen copy of the current user id, or `nil`.
    # @api public
    def user_id
      frozen_copy(store.params[:user_id])
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

    # Returns version of Recorder as +String+
    def version
      VERSION
    end

    private

    # The only place that reads the meta from the store.
    def current_meta
      store.params[:meta]
    end

    # A copy frozen all the way down, which shares nothing with the store.
    def frozen_copy(value)
      deep_freeze(value.deep_dup)
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |nested| deep_freeze(nested) }
      when Array then value.each { |nested| deep_freeze(nested) }
      end
      value.freeze
    end
  end
end

require 'recorder/revision'
