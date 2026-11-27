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

  # Postgres refuses to build an index concurrently inside a transaction, so
  # these examples run outside the one each example normally gets. What they
  # create lives in the throwaway schema below, which is dropped afterwards.
  self.use_transactional_tests = false

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

  # The gem's own options, without Thor's built-ins (`--force`, `--quiet`, ...),
  # which every generator inherits from `Rails::Generators::Base`.
  def recorder_options
    (described_class.class_options.keys - ::Rails::Generators::Base.class_options.keys).map(&:to_s)
  end

  def generated_migrations
    Dir[File.join(destination_root, 'db/migrate/*.rb')].sort
  end

  # Runs every generated migration, in filename order. Nothing is recorded in
  # `schema_migrations` and each one runs outside a transaction of its own, so
  # this establishes that the migrations execute, not that they are reversible.
  def run_generated_migrations
    generated_migrations.each { |path| run_migration(path, :up) }
  end

  # Runs the one generated migration named `name`, in `direction`.
  def run_generated_migration(name, direction = :up)
    run_migration(generated_migrations.find { |path| path.end_with?("_#{name}.rb") }, direction)
  end

  # The migration is evaluated inside a throwaway module rather than `load`ed
  # at top level, because the dummy app ships its own hand-written
  # `CreateRecorderRevisions` — the same constant, declared
  # `ActiveRecord::Migration[6.1]`. `rails_helper` loads it at boot whenever
  # there are migrations to run, so on any Rails but 6.1 defining the generated
  # one at top level raises `TypeError: superclass mismatch`.
  #
  # It only shows up against a database that has not been migrated yet: once the
  # dummy app is up to date, Active Record never loads the migration files and
  # the constant never exists. So it reproduces on a fresh database — CI, or a
  # first local run — and hides everywhere else.
  def run_migration(path, direction)
    was_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false

    namespace = Module.new
    namespace.module_eval(File.read(path), path)
    namespace.constants.each { |name| namespace.const_get(name).new.migrate(direction) }
  ensure
    ActiveRecord::Migration.verbose = was_verbose
  end

  def indexed_columns(connection)
    connection.indexes('recorder_revisions').to_h { |index| [index.name, index.columns] }
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
        expect { run_generated_migrations }.not_to raise_error

        expect(connection.table_exists?('recorder_revisions')).to be(true)
      end
    end

    it 'creates the expected columns' do
      in_isolated_schema do |connection|
        run_generated_migrations

        expect(connection.columns('recorder_revisions').map(&:name)).to contain_exactly(
          'id', 'item_type', 'item_id', 'event', 'data',
          'ip', 'action_date', 'user_id', 'meta', 'created_at'
        )
      end
    end

    it 'sizes the key columns to hold a Rails primary key' do
      in_isolated_schema do |connection|
        run_generated_migrations

        types = connection.columns('recorder_revisions').to_h { |c| [c.name, c.sql_type] }

        expect(types.values_at('item_id', 'user_id')).to eq(%w[bigint bigint])
      end
    end

    it 'indexes the polymorphic item in the order of `ordered_by_created_at`' do
      in_isolated_schema do |connection|
        run_generated_migrations

        expect(indexed_columns(connection))
          .to eq('index_recorder_revisions_on_item_and_created_at' => %w[item_type item_id created_at id])
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
        expect { run_generated_migrations }.not_to raise_error

        expect(connection.indexes('recorder_revisions').map(&:columns)).to include(['user_id'])
      end
    end
  end

  describe '`--with_index_by_item_and_created_at` option' do
    let(:upgrade) { 'add_index_by_item_and_created_at_to_recorder_revisions' }
    let(:item_index) { 'index_recorder_revisions_on_item_type_and_item_id' }
    let(:new_index) { 'index_recorder_revisions_on_item_and_created_at' }
    let(:new_columns) { %w[item_type item_id created_at id] }

    before do
      prepare_destination
      run_generator %w[--with_index_by_item_and_created_at]
    end

    # The table as an earlier install has it, indexed on `(item_type, item_id)`.
    def create_table_with_item_index(connection)
      run_generated_migration('create_recorder_revisions')
      connection.remove_index :recorder_revisions, name: new_index
      connection.add_index :recorder_revisions, %i[item_type item_id], name: item_index
    end

    # A concurrent build that fails leaves its index behind, marked invalid.
    # A unique index over duplicate values fails that way.
    def leave_invalid_index(connection, name)
      connection.execute(<<~SQL.squish)
        INSERT INTO recorder_revisions (item_type, event, data, action_date, created_at)
        VALUES ('Post', 'create', '{}', CURRENT_DATE, now()), ('Post', 'update', '{}', CURRENT_DATE, now())
      SQL
      connection.execute("CREATE UNIQUE INDEX CONCURRENTLY #{name} ON recorder_revisions (item_type)")
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def valid_index?(connection, name)
      connection.select_value(<<~SQL.squish)
        SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass
      SQL
    end

    it 'generates the upgrade migration after the create migration' do
      expect(generated_migrations.map { |path| File.basename(path).sub(/\A\d+_/, '') })
        .to eq(['create_recorder_revisions.rb', "#{upgrade}.rb"])
    end

    it 'replaces the item index of an existing install' do
      in_isolated_schema do |connection|
        create_table_with_item_index(connection)

        run_generated_migration(upgrade)

        expect(indexed_columns(connection)).to eq(new_index => new_columns)
        expect(valid_index?(connection, new_index)).to be(true)
      end
    end

    it 'restores the item index when rolled back' do
      in_isolated_schema do |connection|
        create_table_with_item_index(connection)
        run_generated_migration(upgrade)

        run_generated_migration(upgrade, :down)

        expect(indexed_columns(connection)).to eq(item_index => %w[item_type item_id])
      end
    end

    it 'leaves a fresh install as it is' do
      in_isolated_schema do |connection|
        run_generated_migration('create_recorder_revisions')

        expect { run_generated_migration(upgrade) }.not_to(change { indexed_columns(connection) })
      end
    end

    context 'when an earlier run was interrupted' do
      it 'drops the item index once the new one is built' do
        in_isolated_schema do |connection|
          create_table_with_item_index(connection)
          connection.add_index :recorder_revisions, new_columns, name: new_index

          run_generated_migration(upgrade)

          expect(indexed_columns(connection)).to eq(new_index => new_columns)
        end
      end

      it 'rebuilds the index an interrupted build left invalid' do
        in_isolated_schema do |connection|
          create_table_with_item_index(connection)
          leave_invalid_index(connection, new_index)
          expect(valid_index?(connection, new_index)).to be(false)

          run_generated_migration(upgrade)

          expect(indexed_columns(connection)).to eq(new_index => new_columns)
          expect(valid_index?(connection, new_index)).to be(true)
        end
      end

      it 'rebuilds the item index an interrupted rollback left invalid' do
        in_isolated_schema do |connection|
          create_table_with_item_index(connection)
          run_generated_migration(upgrade)
          leave_invalid_index(connection, item_index)

          run_generated_migration(upgrade, :down)

          expect(indexed_columns(connection)).to eq(item_index => %w[item_type item_id])
          expect(valid_index?(connection, item_index)).to be(true)
        end
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
        expect { run_generated_migrations }.not_to raise_error

        expect(connection.table_exists?('recorder_revisions')).to be(true)
      end
    end
  end
end

# rubocop:enable RSpec/FilePath
