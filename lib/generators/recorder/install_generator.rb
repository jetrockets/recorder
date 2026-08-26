# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Recorder
  # Installs Recorder in a rails app.
  class InstallGenerator < ::Rails::Generators::Base
    include ::Rails::Generators::Migration

    source_root File.expand_path('templates', __dir__)

    class_option(
      :with_index_by_user_id,
      type: :boolean,
      default: false,
      desc: 'Add index by `user_id` column to `recorder_revisions` table'
    )

    desc 'Generates (but does not run) a migration to add a `recorder_revisions` table.'

    def create_migration_file
      add_or_skip_recorder_migration('create_recorder_revisions')
      add_or_skip_recorder_migration('add_index_by_user_id_to_recorder_revisions') if options.with_index_by_user_id?
    end

    def self.next_migration_number(dirname)
      ::ActiveRecord::Generators::Base.next_migration_number(dirname)
    end

    protected

    def add_or_skip_recorder_migration(template)
      migration_dir = File.expand_path('db/migrate', destination_root)
      if self.class.migration_exists?(migration_dir, template)
        ::Kernel.warn "Migration already exists: #{template}"
      else
        migration_template "#{template}.rb.tt", "db/migrate/#{template}.rb"
      end
    end
  end
end
