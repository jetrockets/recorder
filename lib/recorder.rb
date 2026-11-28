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
      store.params.merge!(normalize_info(hash, 'Recorder.info'))
    end

    # Sets Recorder meta information.
    # @api public
    def meta=(hash)
      store.params[:meta] = hash
    end

    # Sets Recorder information for the block only and returns the block's
    # value. Keys follow `info=`. `meta:` is merged into the current meta with
    # symbol keys, or clears it if `nil`; any other key replaces its current
    # value. When the block ends, by returning or raising, the information is
    # restored exactly as it was before the block, writes made inside it
    # through `info=` and `meta=` included. The recording switch is left alone.
    # @raise [ArgumentError] before the block runs, if there is no block, if
    #   the hash sets a column Recorder writes itself, or if `meta:` or the
    #   current meta is neither a Hash nor `nil`
    # @api public
    def with_info(hash)
      raise ArgumentError, 'Recorder.with_info needs a block. To set info for the rest of the request, use Recorder.info=.' unless block_given?

      info = normalize_info(hash, 'Recorder.with_info')
      info[:meta] = merged_meta(info[:meta]) if info.key?(:meta)
      params = store.params
      previous = params.dup

      begin
        params.merge!(info)
        yield
      ensure
        params.replace(previous)
      end
    end

    # Returns the current Recorder information: every key set through
    # `info=`, `meta=` and `with_info`, or an empty Hash. Hashes, Arrays and
    # Strings in it are frozen copies; any other object is the one Recorder
    # holds.
    # @api public
    def info
      params = store.params.dup
      params[:meta] = current_meta if params.key?(:meta)
      frozen_copy(params)
    end

    # Returns the current meta, or `nil`, copied as `info` copies it.
    # @api public
    def meta
      frozen_copy(current_meta)
    end

    # Returns the current user id, or `nil`, copied as `info` copies it.
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

    def normalize_info(hash, writer)
      hash = hash.symbolize_keys
      reserved = hash.keys & RESERVED_INFO_KEYS

      if reserved.any?
        raise ArgumentError, "#{writer} cannot set columns Recorder writes itself: #{reserved.join(", ")}. " \
                             'To date a revision, set action_date.'
      end

      hash
    end

    # The only place that reads the meta from the store.
    def current_meta
      store.params[:meta]
    end

    # A new Hash, so neither the caller's meta nor the current one changes.
    def merged_meta(meta)
      return if meta.nil?
      raise ArgumentError, "Recorder.with_info takes a Hash as meta:, or nil for none, not #{meta.class}." unless meta.is_a?(Hash)

      current = current_meta || {}
      unless current.is_a?(Hash)
        raise ArgumentError, "Recorder.with_info cannot merge meta: into the current meta, a #{current.class}."
      end

      current.symbolize_keys.merge(meta.symbolize_keys)
    end

    # Hashes, Arrays and Strings are copied and frozen, nested ones included;
    # any other object is returned as it is.
    def frozen_copy(value)
      case value
      when Hash then value.transform_values { |nested| frozen_copy(nested) }.freeze
      when Array then value.map { |nested| frozen_copy(nested) }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value
      end
    end
  end
end

require 'recorder/revision'
