# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# `item_id` holds the record's primary key. These examples give the column the
# types `--item_id_type` generates, and others an app may have, and save
# records with integer (Security), UUID (Trade) and string (Currency) keys.
RSpec.describe Recorder::UnsupportedPrimaryKey do
  # Gives `recorder_revisions.item_id` another type for the block, in a
  # savepoint that takes the change back. Saves inside it get savepoints of
  # their own, as they do in the example's transaction. The table is empty at
  # the start of an example, so no value needs converting.
  def with_item_id_type(sql_type)
    ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
      ActiveRecord::Base.connection.execute(
        "ALTER TABLE recorder_revisions ALTER COLUMN item_id TYPE #{sql_type} USING NULL"
      )
      Recorder::Revision.reset_column_information
      yield
      raise ActiveRecord::Rollback
    end
  ensure
    # Drops the cached columns and prepared statements of the altered table.
    Recorder::Revision.reset_column_information
  end

  around do |example|
    if item_id_type
      with_item_id_type(item_id_type) { example.run }
    else
      example.run
    end
  end

  let(:item_id_type) { nil }

  let(:records) do
    {
      Security => -> { Security.create!(name: 'Facebook', identifier: 'FB') },
      Trade => -> { Trade.create!(name: 'Buy FB') },
      Currency => -> { Currency.create!(id: 'USD', name: 'US dollar') }
    }
  end

  # The revisions of a record loaded afresh, so its key is the one the
  # database holds.
  def revisions_found_for(record)
    record.class.find(record.id).revisions
  end

  {
    'bigint' => [Security],
    'integer' => [Security],
    'uuid' => [Trade],
    'character varying' => [Security, Trade, Currency],
    'text' => [Security, Trade, Currency],
    'character(36)' => [],
    'numeric' => []
  }.each do |sql_type, fitting|
    context "when item_id is #{sql_type}" do
      let(:item_id_type) { sql_type }

      fitting.each do |model|
        it "records #{model.name}, whose revisions are found again" do
          record = records.fetch(model).call
          record.update!(name: 'Renamed')

          aggregate_failures do
            expect(revisions_found_for(record).pluck(:event)).to contain_exactly('create', 'update')
            expect(revisions_found_for(record).map(&:item)).to all(eq(record))
          end
        end
      end

      ([Security, Trade, Currency] - fitting).each do |model|
        it "raises for #{model.name} and rolls its create back" do
          expect { records.fetch(model).call }.to raise_error(described_class, /\A#{model.name}'s /)
          expect([model.count, Recorder::Revision.count]).to eq([0, 0])
        end
      end
    end
  end

  it 'leaves item_id as the dummy app has it once the block ends' do
    with_item_id_type('uuid') { Recorder::Revision.columns_hash['item_id'] }

    expect(Recorder::Revision.columns_hash['item_id'].sql_type).to eq('bigint')
  end

  describe 'when item_id is uuid' do
    let(:item_id_type) { 'uuid' }

    it 'stores the UUID itself' do
      trade = Trade.create!(name: 'Buy FB')

      expect(Recorder::Revision.last.item_id).to eq(trade.id)
    end

    it 'records every event' do
      trade = Trade.create!(name: 'Buy FB')
      trade.update!(name: 'Sell FB')
      trade.destroy!

      expect(Recorder::Revision.where(item: trade).pluck(:event)).to contain_exactly('create', 'update', 'destroy')
    end

    it 'records an STI subclass under the base class, where revisions finds it' do
      block_trade = stub_const('BlockTrade', Class.new(Trade)).create!(name: 'Buy 10k FB')

      aggregate_failures do
        expect(Recorder::Revision.last.item_type).to eq('Trade')
        expect(Trade.find(block_trade.id)).to be_a(BlockTrade)
        expect(revisions_found_for(block_trade).count).to eq(1)
      end
    end

    it 'preloads the revisions' do
      trades = [Trade.create!(name: 'Buy FB'), Trade.create!(name: 'Sell FB')]

      loaded = Trade.includes(:revisions).where(id: trades.map(&:id))

      expect(loaded.to_h { |trade| [trade.id, trade.revisions.map(&:item_id)] })
        .to eq(trades.to_h { |trade| [trade.id, [trade.id]] })
    end
  end

  describe 'when item_id is character varying' do
    let(:item_id_type) { 'character varying' }

    # Rails before 7.2 keeps a UUID as it was assigned; the database returns
    # it lowercase and hyphenated.
    {
      'capitals' => 'ABCDEF00-0000-4000-8000-00000000000A',
      'braces' => '{abcdef00-0000-4000-8000-00000000000a}',
      'no hyphens' => 'abcdef0000004000800000000000000a'
    }.each do |form, id|
      it "stores a UUID assigned in #{form} as the database returns it" do
        Trade.create!(id: id, name: 'Buy FB')

        aggregate_failures do
          expect(Recorder::Revision.last.item_id).to eq('abcdef00-0000-4000-8000-00000000000a')
          expect(Trade.find(id).revisions.pluck(:event)).to eq(['create'])
          expect(Trade.includes(:revisions).map { |trade| trade.revisions.size }).to eq([1])
        end
      end
    end

    it 'leaves an item_id that is not a UUID as it is given' do
      Recorder::Tape.record(item_type: 'Trade', item_id: 'not-a-uuid', event: 'create', data: {attributes: {}})

      expect(Recorder::Revision.last.item_id).to eq('not-a-uuid')
    end

    it 'preloads the revisions of integer-keyed records' do
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(Security.includes(:revisions).find(security.id).revisions.map(&:item_id)).to eq([security.id.to_s])
    end
  end

  describe 'a model whose key does not fit' do
    it 'names the model, its key type and the column' do
      expect { Trade.create!(name: 'Buy FB') }.to raise_error(
        described_class,
        "Trade's primary key id (uuid) does not fit recorder_revisions.item_id (bigint), so Recorder cannot " \
        'write its revisions. See "Primary keys" in the Recorder README.'
      )
    end

    def create_unrecorded
      Class.new { include Recorder::Manager }.new.recorder_disabled! { Trade.create!(name: 'Buy FB') }
    end

    it 'raises on update' do
      trade = create_unrecorded

      expect { trade.update!(name: 'Sell FB') }.to raise_error(described_class)
      expect(trade.reload.name).to eq('Buy FB')
    end

    it 'raises on destroy' do
      trade = create_unrecorded

      expect { trade.destroy! }.to raise_error(described_class)
      expect(Trade.where(id: trade.id)).to exist
    end

    it 'raises for an STI subclass, naming the base class' do
      expect { stub_const('BlockTrade', Class.new(Trade)).create!(name: 'Buy 10k FB') }
        .to raise_error(described_class, /\ATrade's primary key id \(uuid\)/)
    end

    it 'raises from a direct Tape call' do
      trade = Trade.new(id: SecureRandom.uuid, name: 'Buy FB')

      expect { Recorder::Tape.new(trade).record_create }.to raise_error(described_class)
    end

    it 'raises from Tape.record given the columns' do
      expect do
        Recorder::Tape.record(item_type: 'Trade', item_id: SecureRandom.uuid, event: 'create', data: {attributes: {}})
      end.to raise_error(described_class)
    end

    it 'writes nothing while recording is off, and does not raise' do
      Recorder.store.recorder_disabled!

      expect { Trade.create!(name: 'Buy FB') }.not_to change(Recorder::Revision, :count)
    end
  end

  # The key's type is the one Active Record casts it with, which the attribute
  # API can set.
  describe 'a key typed through the attribute API' do
    def model_with_key_type(type)
      stub_const('Typed', Class.new(ApplicationRecord) do
        self.table_name = 'securities'
        self.inheritance_column = nil
        include Recorder::Observer
        attribute :id, type
      end).tap(&:recorder)
    end

    it 'is checked by that type' do
      expect { model_with_key_type(:string).create!(name: 'Facebook', identifier: 'FB') }.to raise_error(
        described_class, /\ATyped's primary key id \(string\) does not fit recorder_revisions.item_id \(bigint\)/
      )
    end

    it 'names a type without a name as a custom type' do
      expect { model_with_key_type(Class.new(ActiveModel::Type::Value).new).create!(name: 'Facebook', identifier: 'FB') }
        .to raise_error(described_class, /\ATyped's primary key id \(a custom type\) does not fit/)
    end
  end

  describe 'a model without a single-column primary key' do
    # Rails before 7.1 reports a composite key as none, with a warning.
    let(:leg_class) do
      stub_const('Leg', Class.new(ApplicationRecord) { include Recorder::Observer }).tap do |model|
        model.recorder
        silence_warnings { model.primary_key }
      end
    end

    let(:tick_class) do
      stub_const('Tick', Class.new(ApplicationRecord) { include Recorder::Observer }).tap(&:recorder)
    end

    it 'raises for a composite key' do
      expect { leg_class.create!(trade_id: SecureRandom.uuid, position: 1) }.to raise_error(
        described_class,
        'Leg has no single-column primary key, so Recorder cannot write its revisions. ' \
        'See "Primary keys" in the Recorder README.'
      )
      expect(leg_class.count).to eq(0)
    end

    it 'raises for no key' do
      expect { tick_class.create!(price: 1) }.to raise_error(described_class, /\ATick has no/)
      expect(tick_class.count).to eq(0)
    end
  end

  # `Tape.record` takes the columns as given. An `item_type` that names no
  # model leaves nothing to check the key against.
  describe 'an item_type that names no model' do
    def record(item_type)
      Recorder::Tape.record(item_type: item_type, item_id: 1, event: 'create', data: {attributes: {}})
    end

    ['NoSuchModel', 'Recorder::NoSuchModel', 'Recorder::Config', 'ApplicationRecord', 'trade', ' Trade'].each do |item_type|
      it "writes #{item_type.inspect} unchecked" do
        expect { record(item_type) }.to change(Recorder::Revision, :count).by(1)
      end
    end

    it 'writes the name of a model without a table unchecked' do
      stub_const('Ghost', Class.new(ApplicationRecord))

      expect { record('Ghost') }.to change(Recorder::Revision, :count).by(1)
    end

    it 'leaves a blank one to the validation' do
      expect { record(nil) }.to raise_error(Recorder::RevisionNotSaved, /Item type can't be blank/)
    end
  end

  # The model's file raises while it loads, so the error is the model's, not
  # a sign that `item_type` names nothing.
  describe 'an item_type whose model fails to load' do
    around do |example|
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'broken.rb'), body)
        Object.autoload(:BrokenModel, File.join(dir, 'broken.rb'))
        example.run
      ensure
        Object.send(:remove_const, :BrokenModel) if Object.const_defined?(:BrokenModel, false)
      end
    end

    def record
      Recorder::Tape.record(item_type: 'BrokenModel', item_id: SecureRandom.uuid, event: 'create', data: {attributes: {}})
    end

    {
      'a missing constant' => ['MissingConstant::Here', NameError, /uninitialized constant BrokenModel::MissingConstant/],
      'an undefined name' => ['undefined_macro', NameError, /undefined local variable or method .undefined_macro/],
      'an undefined method' => ['nil.undefined_macro', NoMethodError, /undefined method .undefined_macro/]
    }.each do |cause, (line, error, message)|
      context "with #{cause}" do
        let(:body) { "module BrokenModel\n  #{line}\nend\n" }

        it 'raises the error and writes nothing' do
          expect { record }.to raise_error(error, message)
          expect(Recorder::Revision.count).to eq(0)
        end
      end
    end
  end
end
