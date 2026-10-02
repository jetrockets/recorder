# frozen_string_literal: true

require 'active_record'

module Recorder
  class Revision < ActiveRecord::Base
    self.table_name = 'recorder_revisions'

    if ::Recorder.active_record_protected_attributes?
      attr_accessible(
        :event,
        :user_id,
        :ip,
        :user_agent,
        :action_date,
        :data,
        :meta
      )
    end

    belongs_to :item, polymorphic: true, inverse_of: :revisions, optional: true
    belongs_to :user, optional: true

    validates :item_type, presence: true
    validates :event, presence: true
    validates :action_date, presence: true
    validates :data, presence: true

    scope :ordered_by_created_at, -> { order(created_at: :desc) }

    # def item
    #   return @item if defined?(@item)
    #   return if item_id.nil?

    #   @item = item_type.classify.constantize.new(data['attributes'])

    #   if data['associations'].present?
    #     data['associations'].each do |name, association|
    #       @item.send("build_#{name}", association['attributes'])
    #     end
    #   end

    #   @item
    # end

    # Get changeset for an item
    # @return [Recorder::Changeset]
    def item_changeset
      return @item_changeset if defined?(@item_changeset)
      return nil if item.nil?
      return nil if data['changes'].nil?

      @item_changeset ||= changeset_class(item).new(item, data['changes'])
    end

    # Get names of item associations that carry changes
    # @return [Array]
    def changed_associations
      return [] unless data['associations'].is_a?(Hash)

      data['associations'].select { |_name, association| association_changes(association) }.keys
    end

    # Get changeset for an association
    # @param name [String] name of association to return changeset
    # @return [Recorder::Changeset, nil] nil when the revision holds no changes for it
    def association_changeset(name)
      return nil if item.nil?

      changes = association_changes(data['associations'].try(:[], name.to_s))
      return nil if changes.nil?

      association = item.send(name)
      return nil if association.nil?

      changeset_class(association).new(association, changes)
    end

    protected

    # @api private
    def association_changes(association)
      association['changes'].presence if association.is_a?(Hash)
    end

    # Returns changeset class for passed object.
    # Changeset class name can be overriden with `#recorder_changeset_class` method.
    # If `#recorder_changeset_class` method is not defined, then class name is generated as "#{class}Changeset"
    # @api private
    def changeset_class(object)
      klass = (defined?(Draper) && object.decorated?) ? object.source.class : object.class
      klass = klass.base_class

      return klass.send(:recorder_changeset_class) if klass.respond_to?(:recorder_changeset_class)

      klass = "#{klass}Changeset"

      klass =
        begin
          klass.constantize
        rescue
          nil
        end
      klass.present? ? klass : Recorder::Changeset
    end
  end
end
