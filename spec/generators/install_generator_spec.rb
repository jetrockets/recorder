# frozen_string_literal: true

# rubocop:disable RSpec/FilePath

require 'rails_helper'
require 'generator_spec'
require File.expand_path('../../lib/generators/recorder/install_generator', __dir__)

# These examples run the generated migrations rather than grepping them.
#
# The previous suite asserted on the *text* of the output — `contains 'class
# CreateRecorderRevisions'` — which is why two defects shipped green: a
# migration that raised the moment Rails loaded it, and an option whose
# template was never written.
describe Recorder::InstallGenerator, type: :generator do
  destination File.expand_path('../../../tmp', __FILE__)

  # The dummy app already owns `recorder_revisions` in `public`. Running the
  # generated migration there would collide with it, so each example gets a
  # throwaway schema and the search path is restored afterwards either way.
  def in_isolated_schema
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path

    connection.execute('DROP SCHEMA IF EXISTS recorder_generator_test CASCADE')
    connection.execute('CREATE SCHEMA recorder_generator_test')
    connection.schema_search_path = 'recorder_generator_test'
    connection.schema_cache.clear!

    yield connection
  ensure
    connection.schema_search_path = original_path
    connection.execute('DROP SCHEMA IF EXISTS recorder_generator_test CASCADE')
    connection.schema_cache.clear!
  end

  # The gem's own options, without Thor's built-ins (`--force`, `--quiet`, ...).
  def recorder_options
    described_class.class_options.keys.map(&:to_s).grep(/\Awith_/)
  end

  def generated_migrations
    Dir[File.join(destination_root, 'db/migrate/*.rb')].sort
  end

  # Runs every generated migration, in filename order, the way `rails db:migrate`
  # would.
  #
  # Each one is evaluated inside a throwaway module rather than `load`ed at top
  # level, because the dummy app ships its own hand-written
  # `CreateRecorderRevisions` — the same constant, declared
  # `ActiveRecord::Migration[6.1]`. `rails_helper` loads it at boot whenever
  # there are migrations to run, so on any Rails but 6.1 defining the generated
  # one at top level raises `TypeError: superclass mismatch`.
  #
  # It only shows up against a database that has not been migrated yet: once the
  # dummy app is up to date, Active Record never loads the migration files and
  # the constant never exists. So it reproduces on a fresh database — CI, or a
  # first local run — and hides everywhere else.
  def run_generated_migrations(connection)
    was_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false

    generated_migrations.each do |path|
      namespace = Module.new
      namespace.module_eval(File.read(path), path)
      namespace.constants.each { |name| namespace.const_get(name).new.migrate(:up) }
    end

    connection
  ensure
    ActiveRecord::Migration.verbose = was_verbose
  end

  describe 'no options' do
    before do
      prepare_destination
      run_generator
    end

    it "generates one migration, for the 'recorder_revisions' table" do
      expect(generated_migrations.map { |path| File.basename(path).sub(/\A\d+_/, '') })
        .to eq(['create_recorder_revisions.rb'])
    end

    it 'generates a migration declaring a Rails version' do
      # Rails has rejected a bare `ActiveRecord::Migration` subclass since 5.0,
      # so an unversioned migration runs nowhere.
      expect(File.read(generated_migrations.first))
        .to match(/class CreateRecorderRevisions < ActiveRecord::Migration\[\d+\.\d+\]/)
    end

    it 'generates a migration that runs' do
      in_isolated_schema do |connection|
        expect { run_generated_migrations(connection) }.not_to raise_error

        expect(connection.table_exists?('recorder_revisions')).to be(true)
      end
    end

    it 'creates the expected columns' do
      in_isolated_schema do |connection|
        run_generated_migrations(connection)

        expect(connection.columns('recorder_revisions').map(&:name)).to contain_exactly(
          'id', 'item_type', 'item_id', 'event', 'data',
          'ip', 'action_date', 'user_id', 'meta', 'created_at'
        )
      end
    end

    it 'sizes the key columns to hold a Rails primary key' do
      in_isolated_schema do |connection|
        run_generated_migrations(connection)

        types = connection.columns('recorder_revisions').to_h { |c| [c.name, c.sql_type] }

        expect(types.values_at('item_id', 'user_id')).to eq(%w[bigint bigint])
      end
    end

    it 'indexes the polymorphic item' do
      in_isolated_schema do |connection|
        run_generated_migrations(connection)

        expect(connection.indexes('recorder_revisions').map(&:columns))
          .to include(%w[item_type item_id])
      end
    end
  end

  describe '`--with_index_by_user_id` option' do
    before do
      prepare_destination
      run_generator %w[--with_index_by_user_id]
    end

    it 'generates both migrations' do
      expect(generated_migrations.map { |path| File.basename(path).sub(/\A\d+_/, '') })
        .to eq(['create_recorder_revisions.rb', 'add_index_by_user_id_to_recorder_revisions.rb'])
    end

    it 'generates migrations that run in order' do
      in_isolated_schema do |connection|
        expect { run_generated_migrations(connection) }.not_to raise_error

        expect(connection.indexes('recorder_revisions').map(&:columns)).to include(['user_id'])
      end
    end
  end

  describe 'a destination that already has the migration' do
    before do
      prepare_destination
      run_generator
    end

    it 'warns and writes nothing the second time' do
      allow(Kernel).to receive(:warn)
      already_written = generated_migrations

      run_generator

      expect(generated_migrations).to eq(already_written)
      expect(Kernel).to have_received(:warn).with(/create_recorder_revisions/)
    end
  end

  describe 'advertised options' do
    it 'no longer offers `--with_partitions`' do
      expect(described_class.class_options.key?(:with_partitions)).to be(false)
    end

    # A general guard: if an option is ever added whose template is missing, or
    # whose migration does not run, this fails without anyone remembering to
    # write an example for it.
    it 'dispatches every one to a template that exists and runs' do
      prepare_destination
      run_generator(recorder_options.map { |name| "--#{name}" })

      expect(generated_migrations.length).to eq(recorder_options.length + 1)

      in_isolated_schema do |connection|
        expect { run_generated_migrations(connection) }.not_to raise_error

        expect(connection.table_exists?('recorder_revisions')).to be(true)
      end
    end
  end
end

# rubocop:enable RSpec/FilePath
