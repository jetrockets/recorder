# frozen_string_literal: true

# Mirrors lib/generators/recorder/templates/create_recorder_revisions.rb.tt.
# Keep the two in sync, or the specs stop testing what the generator installs.
class CreateRecorderRevisions < ActiveRecord::Migration[6.1]
  def change
    create_table :recorder_revisions do |t|
      t.string :item_type, null: false
      t.bigint :item_id
      t.string :event, null: false
      t.jsonb :data, null: false
      t.inet :ip
      t.date :action_date, null: false
      t.bigint :user_id
      t.jsonb :meta
      t.datetime :created_at, null: false
    end

    add_index :recorder_revisions, %i[item_type item_id]
  end
end
