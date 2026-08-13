# frozen_string_literal: true

# Spec fixture for the Recorder::Revision `belongs_to :user` association.
class CreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
