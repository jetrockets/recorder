# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_08_13_000001) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "recorder_revisions", force: :cascade do |t|
    t.string "item_type", null: false
    t.integer "item_id"
    t.string "event", null: false
    t.jsonb "data", null: false
    t.inet "ip"
    t.date "action_date", null: false
    t.integer "user_id"
    t.jsonb "meta"
    t.datetime "created_at", null: false
    t.index ["item_type", "item_id"], name: "index_recorder_revisions_on_item_type_and_item_id"
  end

  create_table "securities", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "name", null: false
    t.string "identifier", null: false
    t.integer "settle_days", default: 3, null: false
    t.decimal "pricing_factor", precision: 10, scale: 2, default: "1.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "guard_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

end
