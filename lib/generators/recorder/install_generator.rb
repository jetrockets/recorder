require "rails/generators"
require "rails/generators/active_record"

module Recorder
  # Installs Recorder in a rails app.
  class InstallGenerator < ::Rails::Generators::Base
    include ::Rails::Generators::Migration

    source_root File.expand_path("../templates", __FILE__)

    class_option(
      :with_partitions,
      type: :boolean,
      default: false,
      desc: "Create partitions to `recorder_revisions` table"
    )

    class_option(
      :with_number_column,
      type: :boolean,
      default: false,
      desc: "Add `number` column to `recorder_revisions` table"
    )

    class_option(
      :with_index_by_user_id,
      type: :boolean,
      default: false,
      desc: "Add index by `user_id` column to `recorder_revisions` table"
    )

    desc "Generates (but does not run) a migration to add a `recorder_revisions` table."

    def create_migration_file
      self.add_or_skip_recorder_migration('create_recorder_revisions')
      self.add_or_skip_recorder_migration('add_number_column_to_recorder_revisions') if options.with_number_column?
      self.add_or_skip_recorder_migration('add_index_by_user_id_to_recorder_revisions') if options.with_index_by_user_id?
      self.add_or_skip_recorder_migration('add_partitions_to_recorder_revisions') if options.with_partitions?
    end

    def self.next_migration_number(dirname)
      ::ActiveRecord::Generators::Base.next_migration_number(dirname)
    end

    protected

    def add_or_skip_recorder_migration(migration_name)
      migration_dir = File.expand_path('db/migrate')
      if self.class.migration_exists?(migration_dir, migration_name)
        ::Kernel.warn "Migration already exists: #{migration_name}"
      else
        migration_template("#{migration_name}.rb.erb", "db/migrate/#{migration_name}.rb", migration_version: migration_version)
      end
    end

    def migration_version
      if ::Rails.version.start_with? "5"
        "[#{::Rails::VERSION::MAJOR}.#{::Rails::VERSION::MINOR}]"
      end
    end
  end
end
