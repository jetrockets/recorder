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
      desc: "Create partitions for `revisions` table"
    )

    desc "Generates (but does not run) a migration to add a `revisions` table."

    def create_migration_file
      self.add_or_skip_recorder_migration('create_recorder_revisions')
      self.add_or_skip_recorder_migration('add_partitions_to_recorder_revisions_table') if options.with_partitions?
    end

    def self.next_migration_number(dirname)
      ::ActiveRecord::Generators::Base.next_migration_number(dirname)
    end

  protected

    def add_or_skip_recorder_migration(template)
      migration_dir = File.expand_path('db/migrate')
      if self.class.migration_exists?(migration_dir, template)
        ::Kernel.warn "Migration already exists: #{template}"
      else
        migration_template "#{template}.rb", "db/migrate/#{template}.rb"
      end
    end
  end
end
