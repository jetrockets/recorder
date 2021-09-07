# frozen_string_literal: true

# This migration adds number column to the `revisions` table.
class AddIndexByUserIdToRecorderRevisions < ActiveRecord::Migration
  def change
    add_index :recorder_revisions, :user_id
  end
end
