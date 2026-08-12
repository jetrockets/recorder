# frozen_string_literal: true

# Mirrors lib/generators/recorder/templates/create_recorder_revisions.rb.
#
# Keep the two in sync: this is the table the specs exercise, and if it drifts
# from what the generator installs, the suite stops testing what users run.
#
# The one intentional difference is the versioned `[6.1]` below. The template
# still subclasses a bare ActiveRecord::Migration, which has been unsupported
# since Rails 5 -- fixing that is a separate change.
class CreateRecorderRevisions < ActiveRecord::Migration[6.1]
  def change
    create_table :recorder_revisions do |t|
      t.string :item_type, null: false
      t.integer :item_id
      t.string :event, null: false
      t.jsonb :data, null: false
      t.inet :ip
      t.date :action_date, null: false
      t.integer :user_id
      t.jsonb :meta
      t.datetime :created_at, null: false
    end

    add_index :recorder_revisions, %i[item_type item_id]
  end
end
