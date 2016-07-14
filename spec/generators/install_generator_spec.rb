require "rails_helper"
require "generator_spec"
require File.expand_path("../../../lib/generators/recorder/install_generator", __FILE__)

describe Recorder::InstallGenerator, type: :generator do
  destination File.expand_path("../tmp", __FILE__)

  after(:all) { prepare_destination }

  describe "no options" do
    before(:all) do
      prepare_destination
      run_generator
    end

    it "generates a migration for creating the 'recorder_revisions' table" do
      expect(destination_root).to have_structure {
        directory "db" do
          directory "migrate" do
            migration "create_recorder_revisions" do
              contains "class CreateRecorderRevisions"
              contains "def change"
              contains "create_table :recorder_revisions"
              contains "add_index :recorder_revisions, [:item_type, :item_id]"
            end
          end
        end
      }
    end
  end
end
