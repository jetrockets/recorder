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
end
