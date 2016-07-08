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

  belongs_to :item, :polymorphic => true, :inverse_of => :revisions
  belongs_to :user

  validates :item, :presence => true
  validates :event, :presence => true
  validates :action_date, :presence => true
  validates :data, :presence => true

  scope :ordered_by_created_at, -> { order(:created_at => :desc) }

  def item_changeset
    return @item_changeset if defined?(@item_changeset)

    @item_changeset ||= self.changeset_klass(self.item).new(self.item, self.data['changes'])
  end

  def changed_associations
    self.data['associations'].try(:keys) || []
  end

  def association_changeset(name)
    association = self.item.send(name)
    # association = association.source if association.decorated?

    self.changeset_klass(association).new(association, self.data['associations'].fetch(name.to_s).try(:fetch, 'changes'))
  end

protected

  def changeset_klass(object)
    klass = (defined?(Draper) && object.decorated?) ? object.source.class : object.class
    klass = klass.base_class
    klass = "#{klass}Changeset"

    klass = klass.constantize rescue nil
    klass.present? ? klass : Recorder::Changeset
  end
end
