class CreateSecurities < ActiveRecord::Migration[5.0]
  def change
    create_table :securities do |t|
      t.string :type
      t.string :name, null: false
      t.string :identifier, null: false
      t.integer :settle_days, default: 3, null: false
      t.decimal :pricing_factor, precision: 10, scale: 2, default: 1.0,  null: false
      t.timestamps
    end
  end
end
