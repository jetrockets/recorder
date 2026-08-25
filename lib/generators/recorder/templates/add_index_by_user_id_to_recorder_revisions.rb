# frozen_string_literal: true

# This migration adds an index by `user_id` to the `recorder_revisions` table.
class AddIndexByUserIdToRecorderRevisions < ActiveRecord::Migration
  def change
    add_index :recorder_revisions, :user_id
  end
end
