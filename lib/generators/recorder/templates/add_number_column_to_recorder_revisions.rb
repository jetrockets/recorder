# frozen_string_literal: true

# This migration adds number column to the `revisions` table.
class AddNumberColumnToRecorderRevisions < ActiveRecord::Migration
  def up
    add_column :recorder_revisions, :number, :integer, null: false, default: 0

    execute <<~SQL
            CREATE OR REPLACE FUNCTION get_recorder_revisions_number()
              RETURNS trigger AS
            $BODY$
            BEGIN
                SELECT COALESCE(MAX(recorder_revisions.number), 0) + 1
                INTO NEW.number
                FROM
                  recorder_revisions
                WHERE
                  recorder_revisions.item_type = NEW.item_type
                  AND recorder_revisions.item_id = NEW.item_id;
      #{"      "}
                RETURN NEW;
            END;
            $BODY$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER update_recorder_revisions_number
        BEFORE INSERT ON recorder_revisions FOR EACH ROW
        EXECUTE PROCEDURE get_recorder_revisions_number();
    SQL
  end

  def down
    execute <<-SQL
      DROP TRIGGER update_recorder_revisions_number;
    SQL

    execute <<-SQL
      DROP FUNCTION IF EXISTS get_recorder_revisions_number;
    SQL

    remove_column :recorder_revisions, :number
  end
end
