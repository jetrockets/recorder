# frozen_string_literal: true

# Recorder::Revision `belongs_to :user`, so the dummy app needs somewhere for
# that association to point. The gem itself never defines a User -- host apps
# supply their own -- so this exists purely as a spec fixture.
class CreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
