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
  # Columns Recorder writes itself, which `Recorder.info=` and
  # `Recorder.with_info` cannot set.
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
    # beside it. It holds for the rest of the request or thread, or, inside a
    # `with_info` block, until the block ends.
    # @raise [ArgumentError] if the hash sets a column Recorder writes itself
    # @api public
    def info=(hash)
      store.params.merge!(normalize_info(hash, 'Recorder.info'))
    end

    # Sets Recorder meta information. It holds for the rest of the request or
    # thread, or, inside a `with_info` block, until the block ends.
    # @api public
    def meta=(hash)
      store.params[:meta] = hash
    end

    # Sets Recorder information for the block only and returns the block's
    # value. Keys follow `info=`. `meta:` is merged into the current meta,
    # whose keys stay as they are except those the block sets under either a
    # String or a Symbol, which the block's Symbol keys replace; an empty
    # Hash leaves the meta as it is and `nil` clears it. Any other key
    # replaces its current value. When the block ends, by returning or
    # raising, the information is restored exactly as it was before the
    # block, writes made inside it through `info=` and `meta=` included. The
    # recording switch is left alone.
    # @raise [ArgumentError] before the block runs, if there is no block, if
    #   the hash sets a column Recorder writes itself, if `meta:` is neither a
    #   Hash nor `nil`, or if a non-empty `meta:` would merge into a current
    #   meta that is not a Hash
    # @api public
    def with_info(hash)
      raise ArgumentError, 'Recorder.with_info needs a block. To set info for the rest of the request, use Recorder.info=.' unless block_given?

      info = block_info(hash)
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

    # Returns whatever is stored under `user_id`, normally the id, or `nil`,
    # copied as `info` copies it. A controller whose `current_user` has no
    # `id` stores the object itself, which revisions store as no user; a user
    # set as `user:` is not read here.
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

    # The readers and `with_info` read the current meta through this method.
    def current_meta
      store.params[:meta]
    end

    # The keys a `with_info` block sets. A Hash meta is always a new Hash, so
    # writes into it during the block reach neither the caller's meta nor the
    # one restored afterwards.
    def block_info(hash)
      info = normalize_info(hash, 'Recorder.with_info')
      meta = info.fetch(:meta, {})
      return info if meta.nil?
      raise ArgumentError, "Recorder.with_info takes a Hash as meta:, or nil for none, not #{meta.class}." unless meta.is_a?(Hash)

      current = current_meta
      if meta.any?
        info[:meta] = merged_meta(current, meta)
      elsif current.is_a?(Hash)
        info[:meta] = current.dup
      else
        info.delete(:meta)
      end
      info
    end

    # The current meta's keys stay as they are, but one the block's meta also
    # names, as a String or a Symbol, gives way to the block's Symbol key, so
    # the two never sit side by side.
    def merged_meta(current, meta)
      current ||= {}
      unless current.is_a?(Hash)
        raise ArgumentError, "Recorder.with_info cannot merge meta: into the current meta, a #{current.class}."
      end

      meta = meta.symbolize_keys
      names = meta.keys.map(&:to_s)
      current.reject { |key, _| names.include?(key.to_s) }.merge(meta)
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
