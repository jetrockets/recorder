# This migration adds number column to the `revisions` table.
class AddIndexByUserIdToRecorderRevisions < ActiveRecord::Migration
  def up
    add_index :recorder_revisions, :user_id
  end
end
