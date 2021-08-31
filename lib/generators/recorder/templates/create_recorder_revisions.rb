# This migration creates the `recorder_revisions` table.
class CreateRecorderRevisions < ActiveRecord::Migration
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

    add_index :recorder_revisions, [:item_type, :item_id]
  end
end
