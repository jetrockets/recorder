require 'active_record'

class Recorder::Revision < ActiveRecord::Base
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

  belongs_to :item, polymorphic: true, inverse_of: :revisions
  belongs_to :user

  #validates :item, presence: true
  validates :item_type, presence: true
  validates :event, presence: true
  validates :action_date, presence: true
  validates :data, presence: true

  scope :ordered_by_created_at, -> { order(created_at: :desc) }

  def item
    super || restore_item
  end

  def restore_item
    object = item_type.classify.constantize.new(data['attributes'])

    if data['associations'].present?
      data['associations'].each do |name, association|
        object.send("build_#{name}", association['attributes'])
      end
    end

    object
  end

  # Get changeset for an item
  # @return [Recorder::Changeset]
  def item_changeset
    return @item_changeset if defined?(@item_changeset)
    return nil if self.data['changes'].nil?

    @item_changeset ||= self.changeset_class(self.item).new(self.item, self.data['changes'])
  end

  # Get names of item associations that has been changed
  # @return [Array]
  def changed_associations
    self.data['associations'].try(:keys) || []
  end

  # Get changeset for an association
  # @param name [String] name of association to return changeset
  # @return [Recorder::Changeset]
  def association_changeset(name)
    association = self.item.send(name)
    # association = association.source if association.decorated?

    self.changeset_class(association).new(association, self.data['associations'].fetch(name.to_s).try(:fetch, 'changes'))
  end

protected

  # Returns changeset class for passed object.
  # Changeset class name can be overriden with `#recorder_changeset_class` method.
  # If `#recorder_changeset_class` method is not defined, then class name is generated as "#{class}Changeset"
  # @api private
  def changeset_class(object)
    klass = (defined?(Draper) && object.decorated?) ? object.source.class : object.class
    klass = klass.base_class

    if klass.respond_to?(:recorder_changeset_class)
      return klass.send(:recorder_changeset_class)
    end

    klass = "#{klass}Changeset"

    klass = klass.constantize rescue nil
    klass.present? ? klass : Recorder::Changeset
  end
end
