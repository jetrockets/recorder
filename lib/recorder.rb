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
  # Columns Recorder writes itself, which neither `Recorder.info` nor the
  # column keywords of `Recorder.record` can set.
  RESERVED_INFO_KEYS = %i[id item_type item_id event data created_at].freeze
  private_constant :RESERVED_INFO_KEYS

  # The keys of a revision's `data` that the callbacks write, each holding a
  # Hash, and the keys of each entry under `associations`.
  DATA_KEYS = %w[attributes changes associations].freeze
  ASSOCIATION_DATA_KEYS = %w[attributes changes].freeze
  private_constant :DATA_KEYS, :ASSOCIATION_DATA_KEYS

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

    # Writes a revision of `item` for an event the callbacks do not see, such
    # as a record viewed, approved or exported, in the database transaction
    # open at the time. The model's `if:` and `unless:` are not checked.
    #
    # `data` is stored as given, and a create, update or destroy revision
    # needs its `attributes` snapshot. Every other keyword sets the column of
    # that name over the request's value, `nil` included, except `meta:`, whose
    # Hash is merged into the request's meta. `action_date:` takes a Date,
    # Time or DateTime and stores its date in the application's time zone.
    #
    # @param item [ActiveRecord::Base] a saved record, observed or not
    # @param event [String, Symbol] stored as a String
    # @param data [Hash]
    # @return [Recorder::Revision, nil] the saved revision, or `nil` while
    #   recording is off
    # @raise [ArgumentError] for a record that was never saved or whose id the
    #   `item_id` column cannot hold, a blank event, `data` or `meta:` of the
    #   wrong type, a create, update or destroy without `data[:attributes]`, an
    #   `action_date:` that is not a date or time, and a keyword that is not a
    #   column or names one Recorder writes itself
    # @raise [Recorder::RevisionNotSaved] if the revision fails validation or
    #   a callback halts it
    # @api public
    def record(item, event:, data: {}, **columns)
      revision_columns = Recorder::Tape.revision_columns
      check_item(item, revision_columns.fetch('item_id'))
      check_event(event)
      check_data(data, 'data', DATA_KEYS)
      check_snapshot(data, event)

      Recorder::Tape.write_revision(
        **Recorder::Tape.item_columns(item),
        event: event.to_s,
        data: data,
        **record_columns(columns, revision_columns.keys)
      )
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

    # An id the `item_id` column would store as another value, such as a UUID
    # in a bigint column, would file the revision under another record. The
    # two are compared as text, so an Integer id fits a string column.
    def check_item(item, item_id_type)
      raise ArgumentError, "Recorder.record expects an Active Record object, got #{item.inspect}" unless item.is_a?(ActiveRecord::Base)
      raise ArgumentError, "Recorder.record expects a saved record with an id, got #{item.inspect}" if item.new_record? || item.id.nil?

      stored = item_id_type.cast(item.id)
      return if stored.to_s == item.id.to_s

      raise ArgumentError, "Recorder.record cannot record #{item.class} #{item.id.inspect}: the item_id column " \
                           "would store its id as #{stored.inspect}"
    end

    def check_event(event)
      return if (event.is_a?(String) || event.is_a?(Symbol)) && event.to_s.present?

      raise ArgumentError, "Recorder.record expects event: as a non-blank String or Symbol, got #{event.inspect}"
    end

    # `attributes`, `changes` and `associations` hold Hashes, as they do in the
    # callbacks' revisions, so the readers on `Recorder::Revision` read them.
    def check_data(data, name, keys = [])
      raise ArgumentError, "Recorder.record expects #{name} to be a Hash, got #{data.inspect}" unless data.is_a?(Hash)

      data.each do |key, value|
        next unless keys.include?(key.to_s)

        check_data(value, "#{name}[#{key.inspect}]")
        next unless key.to_s == 'associations'

        value.each do |association, entry|
          check_data(entry, "#{name}[#{key.inspect}][#{association.inspect}]", ASSOCIATION_DATA_KEYS)
        end
      end
    end

    # Replay reads the snapshot of the events the callbacks write.
    def check_snapshot(data, event)
      return unless Recorder::Tape::EVENTS.include?(event.to_s)
      return if data.keys.any? { |key| key.to_s == 'attributes' }

      raise ArgumentError, "Recorder.record expects data[:attributes], a snapshot of the record, for #{event}"
    end

    # Symbolizes the keys. `action_date` and `meta` are converted only when
    # given, so that otherwise the request's values apply.
    def record_columns(columns, column_names)
      columns = columns.symbolize_keys
      check_columns(columns.keys, column_names)
      columns[:action_date] = record_date(columns[:action_date]) if columns.key?(:action_date)
      columns[:meta] = record_meta(columns[:meta]) if columns.key?(:meta)
      columns
    end

    # The table's columns, so that a column an app added is accepted.
    def check_columns(keys, column_names)
      reserved = keys & RESERVED_INFO_KEYS
      raise ArgumentError, "Recorder.record cannot set columns Recorder writes itself: #{reserved.join(", ")}" if reserved.any?

      unknown = keys.map(&:to_s) - column_names
      return if unknown.empty?

      raise ArgumentError, "Recorder.record got #{unknown.join(", ")}, not #{unknown.many? ? "columns" : "a column"} " \
                           'of recorder_revisions'
    end

    # The date in the application's time zone. `nil` leaves `Recorder::Tape`
    # to date the revision today.
    def record_date(value)
      case value
      when ActiveSupport::TimeWithZone, Time, DateTime then value.in_time_zone.to_date
      when Date, nil then value
      else raise ArgumentError, "Recorder.record expects action_date: as a Date, Time or DateTime, got #{value.inspect}"
      end
    end

    # Merged into the request's meta as Symbol keys. The request's own keys
    # stay as they are, less the String and Symbol forms of the keys merged
    # in. `nil` leaves meta out.
    def record_meta(meta)
      return if meta.nil?
      raise ArgumentError, "Recorder.record expects meta: as a Hash or nil, got #{meta.inspect}" unless meta.is_a?(Hash)

      request_meta = store.params[:meta] || {}
      unless request_meta.is_a?(Hash)
        raise ArgumentError, "Recorder.record cannot merge meta: into the request's meta, #{request_meta.inspect}, " \
                             'which is not a Hash'
      end

      meta = meta.symbolize_keys
      names = meta.keys.map(&:to_s)
      request_meta.to_h.reject { |key, _| names.include?(key.to_s) }.merge(meta)
    end
  end
end

require 'recorder/revision'
