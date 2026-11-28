# frozen_string_literal: true

module Recorder
  # Writes attributes of a record with `update_columns` and records the write
  # as an `update` revision, in one transaction. Backs
  # `Recorder::Observer#recorder_update_columns`.
  # @api private
  class UpdateColumns
    attr_reader :record

    def initialize(record)
      @record = record
    end

    # Returns `true`, or `false` when `update_columns` finds no row to update.
    def call(attributes = nil)
      names = attributes ? attributes.keys.map { |key| attribute_name(key) }.uniq : record.changed
      check_writable!(names)
      attributes&.each { |key, value| record.write_attribute(key, value) }
      names &= record.changed
      return true if names.empty?

      write(changes_to(names), changes_to(record.changed - names))
    end

    private

    def attribute_name(key)
      name = key.to_s
      record.class.attribute_aliases[name] || name
    end

    # Raises what `update_columns` raises, before anything is assigned.
    def check_writable!(names)
      raise ActiveRecord::ActiveRecordError, 'cannot update a new record' if record.new_record?
      raise ActiveRecord::ActiveRecordError, 'cannot update a destroyed record' if record.destroyed?
      raise ActiveRecord::ReadOnlyRecord, "#{record.class} is marked as readonly" if record.readonly?

      readonly = names.find { |name| record.class.readonly_attributes.include?(name) }
      raise ActiveRecord::ActiveRecordError, "#{readonly} is marked as readonly" if readonly
    end

    # The value in the database and the value in memory, by attribute name.
    def changes_to(names)
      names.to_h { |name| [name, [record.attribute_in_database(name), record.read_attribute(name)]] }
    end

    # `update_columns` runs first, on the record as the caller left it, so it
    # builds its `WHERE` from the values in the database. A savepoint inside a
    # transaction of the caller's rolls the write back with its revision even
    # when the caller rescues the error.
    def write(written, unsaved)
      updated = record.class.transaction(requires_new: true) { write_and_record(written, unsaved) }
    ensure
      updated ? reassign(unsaved) : unwind(written.merge(unsaved))
    end

    def write_and_record(written, unsaved)
      return false unless record.update_columns(written.transform_values(&:last))

      apply(written, unsaved)
      Recorder::Tape.new(record).record_update if record?
      true
    end

    # Leaves `saved_changes` describing the write, as `touch` does for the
    # attributes it writes: the other changes are set aside first, so
    # `changes_applied` does not take them, and `reassign` puts them back.
    def apply(written, unsaved)
      unsaved.each { |name, (in_database, _)| reset(name, in_database) }
      written.each { |name, change| mark_changed(name, *change) }
      record.changes_applied
    end

    def reassign(unsaved)
      unsaved.each { |name, (_, value)| record.write_attribute(name, value) }
    end

    # Leaves the record as a save that rolls back does: every change unsaved,
    # and `saved_changes` empty.
    def unwind(changes)
      record.clear_changes_information
      changes.each { |name, change| mark_changed(name, *change) }
    end

    def mark_changed(name, from, to)
      reset(name, from)
      record.write_attribute(name, to)
    end

    def reset(name, value)
      record.write_attribute(name, value)
      record.clear_attribute_changes([name])
    end

    # What the `recorder` callbacks check: recording on, then the model's
    # `if:` and `unless:`, which a model whose hierarchy never called
    # `recorder` does not have.
    def record?
      return false unless Recorder.recording?

      conditions = record.class.recorder_conditions
      return false unless conditions

      (conditions[:if].nil? || holds?(conditions[:if])) && !(conditions[:unless] && holds?(conditions[:unless]))
    end

    # Evaluates a condition as Rails does on a callback.
    def holds?(condition)
      return record.send(condition) if condition.is_a?(Symbol)

      condition.arity.zero? ? record.instance_exec(&condition) : record.instance_exec(record, &condition)
    end
  end
end
