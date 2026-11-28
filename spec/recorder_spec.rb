# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder do
  describe '.version' do
    it 'returns the version as a `String`' do
      expect(described_class.version).to be_a(String)
    end

    it 'agrees with `Recorder::VERSION`' do
      expect(described_class.version).to eq(Recorder::VERSION)
    end
  end

  describe '.config' do
    it 'returns the configuration' do
      expect(described_class.config).to equal(Recorder::Config.instance)
    end

    it 'yields the configuration to a block' do
      described_class.config { |config| config.enabled = false }

      expect(described_class.enabled?).to be(false)
    end
  end

  describe '.recording?' do
    it 'is true by default' do
      expect(described_class.recording?).to be(true)
    end

    it 'is false while the process has recording off' do
      described_class.enabled = false

      expect(described_class.recording?).to be(false)
    end

    it 'is false while the request has recording off' do
      described_class.store.recorder_disabled!

      expect(described_class.recording?).to be(false)
    end

    it 'is false in another thread while the process has recording off' do
      described_class.enabled = false

      expect(Thread.new { described_class.recording? }.value).to be(false)
    end

    it 'stays true in another thread while one request has recording off' do
      described_class.store.recorder_disabled!

      expect(Thread.new { described_class.recording? }.value).to be(true)
    end
  end

  describe '.meta=' do
    it 'keeps the meta for the revisions that follow' do
      described_class.meta = {locale: 'en'}

      expect(described_class.store.params[:meta]).to eq(locale: 'en')
    end

    it 'is written on the revisions that follow' do
      described_class.meta = {locale: 'en'}
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to eq('locale' => 'en')
    end
  end

  describe '.info=' do
    it 'keeps the request context for the revisions that follow' do
      described_class.info = {user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1)}

      expect(described_class.store.params).to include(user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1))
    end

    it 'stores a string key as the symbol it replaces' do
      described_class.info = {user_id: 1}
      described_class.info = {'user_id' => 2}

      expect(described_class.store.params).to eq(user_id: 2)
    end

    %i[id item_type item_id event data created_at].each do |column|
      it "refuses #{column}, which Recorder writes itself" do
        expect { described_class.info = {column => 'anything'} }
          .to raise_error(ArgumentError, /cannot set columns Recorder writes itself: #{column}\./)
      end
    end

    it 'refuses a reserved column given as a string key' do
      expect { described_class.info = {'created_at' => Time.current} }
        .to raise_error(ArgumentError, /created_at/)
    end

    it 'keeps none of the hash it refuses' do
      expect { described_class.info = {user_id: 1, created_at: Time.current} }.to raise_error(ArgumentError)

      expect(described_class.store.params).to be_empty
    end
  end

  describe '.record' do
    include ActiveSupport::Testing::TimeHelpers

    let(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }

    def record(item = security, event: :approve, **options)
      described_class.record(item, event: event, **options)
    end

    # Read back from the database, as any reader of the trail sees it.
    def recorded(item = security, event: :approve, **options)
      Recorder::Revision.find(record(item, event: event, **options).id)
    end

    it 'returns the saved revision' do
      revision = record

      aggregate_failures do
        expect(revision).to be_a(Recorder::Revision).and be_persisted
        expect(Recorder::Revision.find(revision.id)).to eq(revision)
      end
    end

    describe 'the item' do
      it 'is stored under the base class of an STI subclass, where revisions finds it' do
        bond = Bond.create!(name: 'Treasury', identifier: 'UST')
        revision = record(bond)

        aggregate_failures do
          expect(revision).to have_attributes(item_type: 'Instrument', item_id: bond.id)
          expect(bond.revisions).to include(revision)
        end
      end

      it 'may be a record of a model that is not observed' do
        user = User.create!(name: 'Igor')

        expect(Recorder::Revision.where(item: user)).to eq([record(user)])
      end

      it 'may be a destroyed record' do
        security.destroy!

        expect(record.item_id).to eq(security.id)
      end

      it 'raises when it was never saved' do
        expect { record(Security.new(name: 'Facebook', identifier: 'FB')) }
          .to raise_error(ArgumentError, /expects a saved record with an id/)
      end

      it 'raises when it was loaded without its id' do
        security

        expect { record(Security.select(:name).first) }.to raise_error(ArgumentError, /expects a saved record with an id/)
      end

      it 'raises when it is not an Active Record object' do
        expect { record(Object.new) }.to raise_error(ArgumentError, /expects an Active Record object/)
      end

      # The dummy's `item_id` is a bigint, which would store this id as
      # 12345678. The table is created inside the example's transaction, so
      # it goes when that rolls back.
      it 'raises, writing nothing, when the item_id column cannot hold its id' do
        ActiveRecord::Base.connection.create_table(:uuid_things, id: :uuid) { |t| t.string :name }
        model = stub_const('UuidThing', Class.new(ApplicationRecord) { self.table_name = 'uuid_things' })
        thing = model.create!(id: '12345678-0000-4000-8000-000000000001', name: 'Facebook')

        expect { record(thing) }
          .to raise_error(ArgumentError, /cannot record UuidThing "12345678-0000-4000-8000-000000000001": .* as 12345678\z/)
        expect(Recorder::Revision.where(item_type: 'UuidThing')).not_to exist
      end

      it 'raises when its id is composite' do
        allow(security).to receive(:id).and_return([security.read_attribute(:id), 2])

        expect { record }.to raise_error(ArgumentError, /would store its id as nil/)
      end
    end

    describe 'the event' do
      it 'is stored as a String' do
        expect(recorded(event: :approve).event).to eq('approve')
      end

      %w[create update destroy].each do |event|
        it "may be #{event}, with data the app computed" do
          data = {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}}

          expect(recorded(event: event, data: data).event).to eq(event)
        end
      end

      [nil, '', ' ', :'', 1].each do |event|
        it "raises for #{event.inspect}" do
          expect { record(event: event) }.to raise_error(ArgumentError, /expects event: as a non-blank String or Symbol/)
        end
      end
    end

    describe 'the data' do
      it 'is stored as given, read back with string keys' do
        data = {note: 'Checked', checks: [{name: 'contract', passed: true}], score: 1.5}

        expect(recorded(data: data).data)
          .to eq('note' => 'Checked', 'checks' => [{'name' => 'contract', 'passed' => true}], 'score' => 1.5)
      end

      it 'is an empty Hash by default' do
        expect(recorded.data).to eq({})
      end

      it 'reads back through the readers when empty' do
        revision = recorded

        aggregate_failures do
          expect(revision.item_changeset).to be_nil
          expect(revision.changed_associations).to eq([])
          expect(revision.association_changeset(:guard)).to be_nil
        end
      end

      # Replaying a record's history reads the snapshot of each of these.
      [:create, :update, :destroy, 'update'].each do |event|
        [{}, {changes: {name: %w[Facebook Meta]}}, {note: 'Imported'}].each do |data|
          it "raises for #{event.inspect} without attributes in #{data.inspect}" do
            expect { record(event: event, data: data) }
              .to raise_error(ArgumentError, /expects data\[:attributes\], a snapshot of the record, for #{event}\z/)
          end
        end
      end

      it 'takes the attributes of an update under a String key' do
        data = {'attributes' => {'name' => 'Meta'}, 'changes' => {'name' => %w[Facebook Meta]}}

        expect(recorded(event: :update, data: data).data['attributes']).to eq('name' => 'Meta')
      end

      it 'writes nothing for an update without attributes' do
        security

        expect { record(event: :update, data: {changes: {name: %w[Facebook Meta]}}) }
          .to raise_error(ArgumentError)
        expect(security.revisions.pluck(:event)).to eq(%w[create])
      end

      it 'reads changes back as a changeset' do
        data = {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}}
        changeset = recorded(event: :update, data: data).item_changeset

        expect([changeset.previous(:name), changeset.next(:name)]).to eq(%w[Facebook Meta])
      end

      it "reads an association's changes back as a changeset" do
        instrument = Instrument.create!(name: 'Instagram', identifier: 'IG', guard: Instrument.create!(name: 'Meta', identifier: 'META'))
        data = {associations: {guard: {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}, note: 'renamed'}}}
        revision = recorded(instrument, data: data)

        aggregate_failures do
          expect(revision.changed_associations).to eq(['guard'])
          expect(revision.association_changeset(:guard).previous(:name)).to eq('Facebook')
        end
      end

      [nil, [], 'Checked'].each do |data|
        it "raises for #{data.inspect}" do
          expect { record(data: data) }.to raise_error(ArgumentError, /expects data to be a Hash/)
        end
      end

      {
        {changes: %w[name]} => 'data[:changes]',
        {'attributes' => 'Facebook'} => 'data["attributes"]',
        {associations: %i[guard]} => 'data[:associations]',
        {associations: {guard: 'Meta'}} => 'data[:associations][:guard]',
        {associations: {'guard' => {changes: 'name'}}} => 'data[:associations]["guard"][:changes]'
      }.each do |data, name|
        it "raises when #{name}, which the readers rely on, is not a Hash" do
          expect { record(data: data) }.to raise_error(ArgumentError, /expects #{Regexp.escape(name)} to be a Hash/)
        end
      end
    end

    describe 'the request context' do
      before do
        described_class.info = {user_id: 7, ip: '10.0.0.1', action_date: Date.new(2020, 1, 1)}
        described_class.meta = {request_id: 'abc'}
      end

      it 'is written where no keyword sets it' do
        expect(recorded).to have_attributes(
          user_id: 7, ip: IPAddr.new('10.0.0.1'), action_date: Date.new(2020, 1, 1), meta: {'request_id' => 'abc'}
        )
      end

      it 'gives way to a keyword' do
        expect(recorded(user_id: 8, ip: '10.0.0.2')).to have_attributes(user_id: 8, ip: IPAddr.new('10.0.0.2'))
      end

      it 'gives way to an explicit nil' do
        expect(recorded(user_id: nil, ip: nil)).to have_attributes(user_id: nil, ip: nil)
      end

      it 'gives way to a keyword given as a string' do
        expect(recorded('user_id' => 8).user_id).to eq(8)
      end
    end

    describe 'meta:' do
      it 'is merged into the request meta, its own keys winning' do
        described_class.meta = {request_id: 'abc', reason: 'Requested'}

        expect(recorded(meta: {reason: 'Scheduled', step: nil}).meta)
          .to eq('request_id' => 'abc', 'reason' => 'Scheduled', 'step' => nil)
      end

      it 'wins over a request key given as the other of String and Symbol' do
        described_class.meta = {'reason' => 'Requested'}

        expect(recorded(meta: {reason: 'Scheduled'}).meta).to eq('reason' => 'Scheduled')
      end

      it 'is written alone when the request has no meta' do
        expect(recorded(meta: {reason: 'Scheduled'}).meta).to eq('reason' => 'Scheduled')
      end

      it 'leaves the request meta out when nil' do
        described_class.meta = {request_id: 'abc'}

        expect(recorded(meta: nil).meta).to be_nil
      end

      it 'leaves the request meta as it was' do
        described_class.meta = {request_id: 'abc'}
        record(meta: {reason: 'Scheduled'})

        expect(described_class.store.params[:meta]).to eq(request_id: 'abc')
      end

      it 'raises for a value that is neither a Hash nor nil' do
        expect { record(meta: 'Scheduled') }.to raise_error(ArgumentError, /expects meta: as a Hash or nil/)
      end

      it 'raises when the request meta is not a Hash' do
        described_class.meta = 'abc'

        expect { record(meta: {reason: 'Scheduled'}) }.to raise_error(ArgumentError, /cannot merge meta: into the request's meta/)
      end
    end

    describe 'action_date:' do
      # At 10:00 UTC only UTC+14 has reached the next day.
      around { |example| Time.use_zone('Pacific/Kiritimati') { example.run } }

      it "stores a Time's date in the application's time zone" do
        expect(recorded(action_date: Time.utc(2026, 10, 2, 10)).action_date).to eq(Date.new(2026, 10, 3))
      end

      it "stores a TimeWithZone's date in the application's time zone" do
        time = Time.utc(2026, 10, 2, 10).in_time_zone('UTC')

        expect(recorded(action_date: time).action_date).to eq(Date.new(2026, 10, 3))
      end

      it "stores a DateTime's date in the application's time zone" do
        expect(recorded(action_date: DateTime.new(2026, 10, 2, 10)).action_date).to eq(Date.new(2026, 10, 3))
      end

      it 'stores a Date as it is' do
        expect(recorded(action_date: Date.new(2020, 1, 1)).action_date).to eq(Date.new(2020, 1, 1))
      end

      it "is the request's date when not given" do
        described_class.info = {action_date: Date.new(2020, 1, 1)}

        expect(recorded.action_date).to eq(Date.new(2020, 1, 1))
      end

      it "is today in the application's time zone when neither it nor the request gives one" do
        travel_to(Time.utc(2026, 10, 2, 10)) do
          expect(recorded.action_date).to eq(Date.new(2026, 10, 3))
        end
      end

      it 'is today when nil, though the request gives a date' do
        described_class.info = {action_date: Date.new(2020, 1, 1)}

        travel_to(Time.utc(2026, 10, 2, 10)) do
          expect(recorded(action_date: nil).action_date).to eq(Date.new(2026, 10, 3))
        end
      end

      it 'raises for a String' do
        expect { record(action_date: '2020-01-01') }
          .to raise_error(ArgumentError, /expects action_date: as a Date, Time or DateTime/)
      end
    end

    describe 'other columns' do
      it 'sets a column the app added' do
        expect(recorded(title: 'Approved').title).to eq('Approved')
      end

      it 'raises for a keyword that is not a column' do
        expect { record(note: 'Checked') }.to raise_error(ArgumentError, /got note, not a column of recorder_revisions/)
      end

      it 'raises for several keywords that are not columns' do
        expect { record(note: 'Checked', item: security) }.to raise_error(ArgumentError, /got note, item, not columns/)
      end

      # `event` and `data` have keywords of their own, so only a String key
      # reaches the column keywords.
      [:id, :item_type, :item_id, :created_at, 'event', 'data'].each do |column|
        it "raises for #{column.inspect}, which Recorder writes itself" do
          expect { record(column => 'anything') }
            .to raise_error(ArgumentError, /cannot set columns Recorder writes itself: #{column}\z/)
        end
      end
    end

    describe 'while recording is off' do
      before { security }

      it 'writes nothing and returns nil while the process has recording off' do
        described_class.enabled = false

        expect { expect(record).to be_nil }.not_to change(Recorder::Revision, :count)
      end

      it 'writes nothing and returns nil inside recorder_disabled!' do
        manager = Object.new.extend(Recorder::Manager)

        manager.recorder_disabled! do
          expect { expect(record).to be_nil }.not_to change(Recorder::Revision, :count)
        end
      end

      it 'still raises for an argument it refuses' do
        described_class.enabled = false

        expect { record(event: '') }.to raise_error(ArgumentError)
      end
    end

    it "does not check the model's if: and unless:" do
      model = stub_const('Gated', Class.new(ApplicationRecord) do
        include Recorder::Observer

        self.table_name = 'securities'
        self.inheritance_column = nil

        recorder if: -> { false }
      end)
      gated = model.create!(name: 'Facebook', identifier: 'FB')

      expect { record(gated) }.to change { gated.revisions.count }.from(0).to(1)
    end

    it 'raises RevisionNotSaved, carrying the revision, when the revision fails validation' do
      allow(Recorder::Revision).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |revision| revision.action_date = nil }
      end

      expect { record }.to raise_error(Recorder::RevisionNotSaved, /Action date can't be blank/) do |error|
        expect(error.record).to be_a(Recorder::Revision)
      end
    end

    describe 'in a transaction' do
      # Examples already run inside a transaction, so a rollback needs a
      # savepoint of its own.
      def roll_back
        ActiveRecord::Base.transaction(requires_new: true) do
          yield
          raise ActiveRecord::Rollback
        end
      end

      before { security }

      it 'is written before the transaction commits' do
        roll_back do
          record

          expect(security.revisions.pluck(:event)).to include('approve')
        end
      end

      it 'rolls back with the transaction' do
        expect { roll_back { record } }.not_to change(Recorder::Revision, :count)
      end

      it 'leaves the revision it returned unsaved when the transaction rolls back' do
        revision = nil
        roll_back { revision = record }

        expect(revision).not_to be_persisted
      end
    end
  end
end
