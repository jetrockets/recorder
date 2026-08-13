# frozen_string_literal: true

class AddGuardToSecurities < ActiveRecord::Migration[6.1]
  def change
    add_column :securities, :guard_id, :integer
  end
end
