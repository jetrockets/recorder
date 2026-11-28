# frozen_string_literal: true

module Recorder
  # Writes attributes of a record with `update_columns` and records the write
  # as an `update` revision, in one transaction. Backs
  # `Recorder::Observer#recorder_update_columns`.
  # @api private
  class UpdateColumns
    REVISION_PENDING_MESSAGE = 'recorder_update_columns cannot run while the record is being created or updated ' \
      'and Recorder has not written that revision yet: in before_update, around_create or around_update, or in ' \
      'an after_create or after_update declared above `recorder`. Call it from after_save, or declare the ' \
      'callback below `recorder`.'

    attr_reader :record

    def initialize(record)
      @record = record
    end

    # Returns `true`, or `false` when nothing was written: there was no row to
    # update, or a callback raised `ActiveRecord::Rollback`.
    def call(attributes = nil)
      names = attributes ? attributes.keys.map { |key| attribute_name(key) }.uniq : record.changed
      check_record!
      check_attributes!(names)
      attributes&.each { |key, value| record.write_attribute(key, value) }
      names &= record.changed & record.class.column_names
      return true if names.empty?

      write(changes_to(names), changes_to(record.changed - names)) == true
    end

    private

    # Resolves a key as `write_attribute` does.
    def attribute_name(key)
      name = key.to_s
      name = record.class.attribute_aliases[name] || name
      return name unless name == 'id'

      record.class.primary_key || name
    end

    # Raises what `update_columns` raises for the record, before anything is
    # assigned, and refuses to replace `saved_changes` that Recorder has yet to
    # record.
    def check_record!
      raise ActiveRecord::ActiveRecordError, 'cannot update a new record' if record.new_record?
      raise ActiveRecord::ActiveRecordError, 'cannot update a destroyed record' if record.destroyed?
      raise ActiveRecord::ReadOnlyRecord, "#{record.class} is marked as readonly" if record.readonly?
      return unless record.instance_variable_defined?(Recorder::Observer::REVISION_PENDING)

      raise ActiveRecord::ActiveRecordError, REVISION_PENDING_MESSAGE
    end

    # Every attribute it writes, and every other unsaved change it sets aside
    # and puts back, has to be assignable and to have a value in the database.
    # For a column the record did not load, Active Model reports that value as
    # a bare Object.
    def check_attributes!(names)
      changed = record.changed
      readonly = (names | changed).find { |name| record.class.readonly_attributes.include?(name) }
      raise ActiveRecord::ActiveRecordError, "#{readonly} is marked as readonly" if readonly

      missing = names.find { |name| !record.has_attribute?(name) } ||
        changed.find { |name| record.attribute_in_database(name).instance_of?(Object) }
      raise ActiveModel::MissingAttributeError, "missing attribute '#{missing}' for #{record.class}" if missing
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
      previously_new_record = record.previously_new_record?
      updated = record.class.transaction(requires_new: true) { write_and_record(written, unsaved) }
    ensure
      updated ? reassign(unsaved) : unwind(written.merge(unsaved), previously_new_record)
    end

    def write_and_record(written, unsaved)
      return false unless record.update_columns(written.transform_values(&:last))

      apply(written, unsaved)
      Recorder::Tape.new(record).record_update if record?
      true
    end

    # Leaves the record as an update of the written attributes leaves it.
    # `saved_changes` describes the write, as `touch` does for the attributes
    # it writes: the other changes are set aside first, so `changes_applied`
    # does not take them, and `reassign` puts them back. `previously_new_record?`
    # reads `@previously_new_record`, which an update clears; Active Record has
    # no public writer for it.
    def apply(written, unsaved)
      unsaved.each { |name, (in_database, _)| reset(name, in_database) }
      written.each { |name, change| mark_changed(name, *change) }
      record.changes_applied
      record.instance_variable_set(:@previously_new_record, false)
    end

    def reassign(unsaved)
      unsaved.each { |name, (_, value)| record.write_attribute(name, value) }
    end

    # Leaves the record as a save that rolls back does: every change unsaved,
    # `saved_changes` empty and `previously_new_record?` as it was.
    def unwind(changes, previously_new_record)
      record.clear_changes_information
      changes.each { |name, change| mark_changed(name, *change) }
      record.instance_variable_set(:@previously_new_record, previously_new_record)
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

      conditions = record.class.send(:recorder_conditions)
      return false unless conditions

      (conditions[:if].nil? || holds?(conditions[:if])) && !(conditions[:unless] && holds?(conditions[:unless]))
    end

    # Evaluates a condition as Rails does on a callback, for the forms
    # `Recorder::Options.validate_condition` admits: a method name, or a Proc
    # that takes the record or nothing.
    def holds?(condition)
      return record.send(condition) if condition.is_a?(Symbol)

      condition.arity.zero? ? record.instance_exec(&condition) : record.instance_exec(record, &condition)
    end
  end
end
