# frozen_string_literal: true

# Spec fixtures for models whose primary key is not an integer: a UUID, a
# string, two columns, and none.
class CreateTablesWithOtherKeys < ActiveRecord::Migration[6.1]
  def change
    create_table :trades, id: :uuid do |t|
      t.string :type
      t.string :name, null: false
    end

    create_table :currencies, id: :string do |t|
      t.string :name, null: false
    end

    create_table :legs, primary_key: %i[trade_id position] do |t|
      t.uuid :trade_id
      t.integer :position
    end

    create_table :ticks, id: false do |t|
      t.decimal :price, null: false
    end
  end
end
