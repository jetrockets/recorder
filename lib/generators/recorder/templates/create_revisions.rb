# This migration creates the `revisions` table.
class CreateRevisions < ActiveRecord::Migration
  def change
    create_table :recorder_revisions do |t|
      t.string :item_type, null: false
      t.integer :item_id, null: false
      t.string :event, null: false
      t.jsonb :data, null: false
      t.inet :ip
      t.date :action_date, null: false
      t.integer :user_id
      t.jsonb :meta
      t.datetime :created_at, null: false
    end

    add_index :revisions, [:item_type, :item_id]
  end
end
