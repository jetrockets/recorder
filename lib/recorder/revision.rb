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

    belongs_to :user

    validates :item_type, presence: true
    validates :event, presence: true
    validates :action_date, presence: true
    validates :data, presence: true

    scope :ordered_by_created_at, -> { order(created_at: :desc) }

    def item
      return @item if defined?(@item)
      return if item_id.nil?

      @item = item_type.classify.constantize.new(data['attributes'])

      if data['associations'].present?
        data['associations'].each do |name, association|
          @item.send("build_#{name}", association['attributes'])
        end
      end

      @item
    end

    # Get changeset for an item
    # @return [Recorder::Changeset]
    def item_changeset
      return @item_changeset if defined?(@item_changeset)
      return nil if item.nil?
      return nil if data['changes'].nil?

      @item_changeset ||= changeset_class(item).new(item, data['changes'])
    end

    # Get names of item associations that has been changed
    # @return [Array]
    def changed_associations
      data['associations'].try(:keys) || []
    end

    # Get changeset for an association
    # @param name [String] name of association to return changeset
    # @return [Recorder::Changeset]
    def association_changeset(name)
      association = item.send(name)
      # association = association.source if association.decorated?

      changeset_class(association).new(association, data['associations'].fetch(name.to_s).try(:fetch, 'changes'))
    end

    protected

    # Returns changeset class for passed object.
    # Changeset class name can be overriden with `#recorder_changeset_class` method.
    # If `#recorder_changeset_class` method is not defined, then class name is generated as "#{class}Changeset"
    # @api private
    def changeset_class(object)
      klass = defined?(Draper) && object.decorated? ? object.source.class : object.class
      klass = klass.base_class

      return klass.send(:recorder_changeset_class) if klass.respond_to?(:recorder_changeset_class)

      klass = "#{klass}Changeset"

      klass = begin
        klass.constantize
      rescue
        nil
      end
      klass.present? ? klass : Recorder::Changeset
    end
  end
end
