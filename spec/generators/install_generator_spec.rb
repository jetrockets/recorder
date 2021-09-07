# frozen_string_literal: true

# rubocop:disable RSpec/FilePath

require 'rails_helper'
require 'generator_spec'
require File.expand_path('../../lib/generators/recorder/install_generator', __dir__)

describe Recorder::InstallGenerator, type: :generator do
  destination File.expand_path('tmp', __dir__)

  after(:all) { prepare_destination }

  describe 'no options' do
    before(:all) do
      prepare_destination
      run_generator
    end

    it "generates a migration for creating the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory 'db' do
          directory 'migrate' do
            migration 'create_recorder_revisions' do
              contains 'class CreateRecorderRevisions'
              contains 'def change'
              contains 'create_table :recorder_revisions'
              contains 'add_index :recorder_revisions, [:item_type, :item_id]'
            end
          end
        end
      }
    end
  end

  describe '`--with_number_column` option' do
    before(:all) do
      prepare_destination
      run_generator %w[--with_number_column]
    end

    it "generates a migration for creating the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory 'db' do
          directory 'migrate' do
            migration 'create_recorder_revisions' do
              contains 'class CreateRecorderRevisions'
              contains 'def change'
              contains 'create_table :recorder_revisions'
              contains 'add_index :recorder_revisions, [:item_type, :item_id]'
            end
          end
        end
      }
    end

    it "generates a migration for adding 'number' column to the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory 'db' do
          directory 'migrate' do
            migration 'add_number_column_to_recorder_revisions' do
              contains 'class AddNumberColumnToRecorderRevisions'
              contains 'def up'
              contains 'add_column :recorder_revisions, :number'
              contains 'CREATE OR REPLACE FUNCTION get_recorder_revisions_number()'
              contains 'CREATE TRIGGER update_recorder_revisions_number'
              contains 'def down'
              contains 'DROP TRIGGER update_recorder_revisions_number;'
              contains 'DROP FUNCTION IF EXISTS get_recorder_revisions_number;'
              contains 'remove_column :recorder_revisions, :number'
            end
          end
        end
      }
    end
  end

  describe '`--with_index_by_user_id` option' do
    before(:all) do
      prepare_destination
      run_generator %w[--with_index_by_user_id]
    end

    it "generates a migration for creating the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory 'db' do
          directory 'migrate' do
            migration 'create_recorder_revisions' do
              contains 'class CreateRecorderRevisions'
              contains 'def change'
              contains 'create_table :recorder_revisions'
              contains 'add_index :recorder_revisions, [:item_type, :item_id]'
            end
          end
        end
      }
    end

    it "generates a migration for adding index by 'user_id' column in the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory 'db' do
          directory 'migrate' do
            migration 'add_index_by_user_id_to_recorder_revisions' do
              contains 'class AddIndexByUserIdToRecorderRevisions'
              contains 'def change'
              contains 'add_index :recorder_revisions, :user_id'
            end
          end
        end
      }
    end
  end
end

# rubocop:enable RSpec/FilePath
