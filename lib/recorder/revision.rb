# frozen_string_literal: true

require 'active_record'

module Recorder
  class Revision < ActiveRecord::Base
    self.table_name = 'recorder_revisions'

    belongs_to :item, polymorphic: true, inverse_of: :revisions, optional: true
    belongs_to :user, optional: true

    validates :item_type, presence: true
    validates :event, presence: true
    validates :action_date, presence: true
    validates :data, presence: true

    # Newest first. Revisions written in the same instant fall back to the
    # order they were inserted in.
    scope :ordered_by_created_at, -> { order(created_at: :desc, id: :desc) }

    # Get changeset for an item
    # @return [Recorder::Changeset]
    def item_changeset
      return @item_changeset if defined?(@item_changeset)

      @item_changeset = changeset_class(item).new(item, data['changes']) if item && data['changes']
    end

    # Get names of item associations that carry changes
    # @return [Array]
    def changed_associations
      recorded_associations.select { |_name, entry| association_changes(entry) }.keys
    end

    # Get changeset for an association
    # @param name [String] name of association to return changeset
    # @return [Recorder::Changeset, nil] nil when the revision holds no changes for it
    def association_changeset(name)
      return nil if item.nil?

      changes = association_changes(recorded_associations[name.to_s])
      return nil if changes.nil?

      association = item.send(name)
      return nil if association.nil?

      changeset_class(association).new(association, changes)
    end

    protected

    # @api private
    def recorded_associations
      data['associations'].is_a?(Hash) ? data['associations'] : {}
    end

    # @api private
    def association_changes(entry)
      entry['changes'].presence if entry.is_a?(Hash)
    end

    # The model's `recorder_changeset_class`, else `"#{Model}Changeset"` when
    # that constant exists, else `Recorder::Changeset`.
    # @api private
    def changeset_class(object)
      model = (defined?(Draper) && object.decorated?) ? object.source.class : object.class
      model = model.base_class

      return model.recorder_changeset_class if model.respond_to?(:recorder_changeset_class)

      "#{model}Changeset".safe_constantize || Recorder::Changeset
    end
  end

  # Raised from the save of an observed record when its revision fails
  # validation or a callback halts it. `record` is the revision.
  class RevisionNotSaved < ActiveRecord::RecordNotSaved; end
end
