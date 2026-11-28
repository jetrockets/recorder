# frozen_string_literal: true

require 'rails_helper'

# Reached through `Recorder::Observer#recorder_update_columns`.
RSpec.describe Recorder::UpdateColumns do
  # Throwaway models: `.recorder` registers callbacks, which outlive an example.
  def securities_model(name, &block)
    stub_const(name, Class.new(ApplicationRecord) { self.table_name = 'securities' }).tap do |model|
      model.include(Recorder::Observer)
      model.class_eval(&block) if block
    end
  end

  def revisions(record, event: 'update')
    Recorder::Revision.where(item_type: record.class.polymorphic_name, item_id: record.id, event: event)
      .order(:created_at, :id)
  end

  def row(record)
    record.class.find(record.id)
  end

  # The UPDATE statements run on `securities` inside the block.
  def updates
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].start_with?('UPDATE "securities"') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
    statements
  end

  # Hands each revision to the block after Recorder builds it, before it is
  # saved.
  def each_revision
    allow(Recorder::Revision).to receive(:new).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap { |revision| yield revision }
    end
  end

  def fail_revision_validation
    each_revision { |revision| revision.item_type = nil }
  end

  let!(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }

  describe 'the write' do
    it 'writes the attributes of a Hash without validations or callbacks, and returns true' do
      model = securities_model('Strict')
      model.class_eval do
        recorder
        validates :name, length: {maximum: 8}
        before_update { raise 'a callback ran' }
      end
      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect(record.recorder_update_columns(name: 'Meta Platforms')).to be(true)
        expect(row(record).name).to eq('Meta Platforms')
      end
    end

    it 'writes the unsaved changes when called without attributes' do
      security.name = 'Meta'
      security.settle_days = 5

      aggregate_failures do
        expect(security.recorder_update_columns).to be(true)
        expect(row(security).attributes).to include('name' => 'Meta', 'settle_days' => 5)
      end
    end

    it 'writes an attribute changed in place' do
      security.name << ' Inc.'
      security.recorder_update_columns

      expect(row(security).name).to eq('Facebook Inc.')
    end

    it 'writes only the attributes whose value changes' do
      Security.where(id: security.id).update_all(identifier: 'XX')

      statements = updates { security.recorder_update_columns(name: 'Meta', identifier: 'FB') }

      aggregate_failures do
        expect(statements.size).to eq(1)
        expect(statements.first).not_to include('identifier')
        expect(row(security).attributes).to include('name' => 'Meta', 'identifier' => 'XX')
        expect(revisions(security).last.data['changes'].keys).to eq(%w[name])
      end
    end

    it 'casts the values as an assignment does' do
      security.recorder_update_columns(settle_days: '5')

      aggregate_failures do
        expect(security.saved_changes).to eq('settle_days' => [3, 5])
        expect(revisions(security).last.data['changes']).to eq('settle_days' => [3, 5])
      end
    end

    it 'takes string keys and attribute aliases' do
      model = securities_model('Aliased')
      model.class_eval do
        recorder
        alias_attribute :title, :name
      end
      record = model.create!(name: 'Facebook', identifier: 'FB')
      record.recorder_update_columns('title' => 'Meta', 'identifier' => 'META')

      aggregate_failures do
        expect(row(record).attributes).to include('name' => 'Meta', 'identifier' => 'META')
        expect(revisions(record).last.data['changes']).to eq('name' => %w[Facebook Meta], 'identifier' => %w[FB META])
      end
    end
  end

  describe 'when nothing changes' do
    it 'writes and records nothing, and returns true' do
      security.name = 'Meta'
      security.name = 'Facebook'

      aggregate_failures do
        [[{name: 'Facebook', identifier: 'FB'}], [{}], []].each do |args|
          result = nil
          expect { expect(updates { result = security.recorder_update_columns(*args) }).to be_empty }
            .not_to change(Recorder::Revision, :count)
          expect(result).to be(true)
        end
      end
    end
  end

  describe 'the dirty state afterwards' do
    it 'describes the write in saved_changes and previous_changes, and leaves changes empty' do
      security.recorder_update_columns(name: 'Meta')

      aggregate_failures do
        expect(security.saved_changes).to eq('name' => %w[Facebook Meta])
        expect(security.previous_changes).to eq('name' => %w[Facebook Meta])
        expect(security.saved_change_to_name?).to be(true)
        expect(security.name_before_last_save).to eq('Facebook')
        expect(security.changes).to eq({})
        expect(security.name_in_database).to eq('Meta')
      end
    end

    it 'does the same for the unsaved changes it writes' do
      security.name = 'Meta'
      security.recorder_update_columns

      aggregate_failures do
        expect(security.saved_changes).to eq('name' => %w[Facebook Meta])
        expect(security.changes).to eq({})
      end
    end

    it 'leaves other unsaved changes unwritten, unrecorded and unsaved' do
      security.settle_days = 7
      security.recorder_update_columns(name: 'Meta')
      revision = revisions(security).last

      aggregate_failures do
        expect(row(security).settle_days).to eq(3)
        expect(security.saved_changes.keys).to eq(%w[name])
        expect(security.changes).to eq('settle_days' => [3, 7])
        expect(revision.data['changes'].keys).to eq(%w[name])
        expect(revision.data['attributes']).to include('name' => 'Meta', 'settle_days' => 3)
      end

      security.save!
      expect(row(security).settle_days).to eq(7)
    end

    it 'leaves previously_new_record? as update_columns leaves it' do
      security.recorder_update_columns(name: 'Meta')

      aggregate_failures do
        expect(security.previously_new_record?).to be(true)
        expect(security.saved_change_to_id?).to be(false)
      end
    end

    it 'leaves the record with the instance variables update_columns leaves' do
      security.recorder_update_columns(name: 'Meta')
      unrecorded = Security.create!(name: 'Facebook', identifier: 'FB').tap { |record| record.update_columns(name: 'Meta') }

      expect(security.instance_variables).to match_array(unrecorded.instance_variables)
    end
  end

  describe 'updated_at' do
    it 'is left as it is, as update_columns leaves it' do
      updated_at = row(security).updated_at
      security.recorder_update_columns(name: 'Meta')

      aggregate_failures do
        expect(row(security).updated_at).to eq(updated_at)
        expect(revisions(security).last.data['changes'].keys).to eq(%w[name])
      end
    end

    it 'is written and recorded when it is passed' do
      time = 1.day.from_now.change(usec: 0)
      security.recorder_update_columns(name: 'Meta', updated_at: time)

      aggregate_failures do
        expect(row(security).updated_at).to eq(time)
        expect(revisions(security).last.data['changes'].keys).to contain_exactly('name', 'updated_at')
      end
    end

    it 'stays out of the revision under ignore:' do
      instrument = Instrument.create!(name: 'Treasury', identifier: 'UST')
      instrument.recorder_update_columns(name: 'Bill', updated_at: 1.day.from_now)

      expect(revisions(instrument).last.data['changes'].keys).to eq(%w[name])
    end
  end

  describe 'the revision' do
    it 'is one update revision whose changes are the write and whose snapshot is the row' do
      expect { security.recorder_update_columns(name: 'Meta', settle_days: 5) }
        .to change(Recorder::Revision, :count).by(1)

      revision = revisions(security).last
      aggregate_failures do
        expect(revision.data['changes']).to eq('name' => %w[Facebook Meta], 'settle_days' => [3, 5])
        expect(revision.data['attributes']).to eq(JSON.parse(row(security).attributes.to_json))
        expect(revision.data).not_to have_key('associations')
      end
    end

    it 'applies ignore:' do
      instrument = Instrument.create!(name: 'Treasury', identifier: 'UST')

      aggregate_failures do
        expect { instrument.recorder_update_columns(identifier: 'T') }.not_to change(Recorder::Revision, :count)
        expect(row(instrument).identifier).to eq('T')

        instrument.recorder_update_columns(name: 'Bill', identifier: 'B')
        revision = revisions(instrument).last
        expect(revision.data['changes']).to eq('name' => %w[Treasury Bill])
        expect(revision.data['attributes']).not_to have_key('identifier')
      end
    end

    it 'applies only:' do
      model = securities_model('Named') { recorder only: %i[name] }
      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect { record.recorder_update_columns(settle_days: 5) }.not_to change(Recorder::Revision, :count)

        record.recorder_update_columns(name: 'Meta', settle_days: 7)
        expect(revisions(record).last.data).to eq('attributes' => {'name' => 'Meta'},
          'changes' => {'name' => %w[Facebook Meta]})
      end
    end

    it 'lets a changes: callback see saved_change_to_*?' do
      model = securities_model('Renamed') { recorder changes: ->(event) { {renamed: [event, saved_change_to_name?]} } }
      record = model.create!(name: 'Facebook', identifier: 'FB')
      record.recorder_update_columns(name: 'Meta')

      expect(revisions(record).last.data['changes']).to eq('name' => %w[Facebook Meta], 'renamed' => ['update', true])
    end
  end

  describe 'the transaction' do
    # Examples already run inside a transaction, so a rollback needs a
    # savepoint of its own.
    def roll_back
      ActiveRecord::Base.transaction(requires_new: true) do
        yield
        raise ActiveRecord::Rollback
      end
    end

    it 'rolls the write back when the revision cannot be written' do
      security.settle_days = 7
      fail_revision_validation

      aggregate_failures do
        expect { security.recorder_update_columns(name: 'Meta') }.to raise_error(Recorder::RevisionNotSaved)
        expect(row(security).attributes).to include('name' => 'Facebook', 'settle_days' => 3)
        expect(revisions(security)).to be_empty
      end
    end

    it 'leaves the record as a save that rolls back does' do
      security.settle_days = 7
      fail_revision_validation
      expect { security.recorder_update_columns(name: 'Meta') }.to raise_error(Recorder::RevisionNotSaved)

      aggregate_failures do
        expect(security.changes).to eq('name' => %w[Facebook Meta], 'settle_days' => [3, 7])
        expect(security.saved_changes).to eq({})
      end
    end

    it 'rolls the write back inside a transaction that rescues the error' do
      fail_revision_validation

      ActiveRecord::Base.transaction do
        security.recorder_update_columns(name: 'Meta')
      rescue Recorder::RevisionNotSaved
        nil
      end

      aggregate_failures do
        expect(row(security).name).to eq('Facebook')
        expect(revisions(security)).to be_empty
      end
    end

    it 'rolls back with a transaction around it' do
      roll_back { security.recorder_update_columns(name: 'Meta') }

      aggregate_failures do
        expect(row(security).name).to eq('Facebook')
        expect(revisions(security)).to be_empty
      end
    end

    it 'writes the revision before the transaction commits' do
      roll_back do
        security.recorder_update_columns(name: 'Meta')

        expect(revisions(security).count).to eq(1)
      end
    end

    it 'leaves the record as a save that rolls back does when the write fails' do
      security.settle_days = 7

      aggregate_failures do
        expect { security.recorder_update_columns(name: nil) }.to raise_error(ActiveRecord::NotNullViolation)
        expect(security.changes).to eq('name' => ['Facebook', nil], 'settle_days' => [3, 7])
        expect(security.saved_changes).to eq({})
        expect(revisions(security)).to be_empty
      end
    end

    it 'returns false and records nothing when there is no row to update' do
      Security.where(id: security.id).delete_all

      aggregate_failures do
        expect(security.recorder_update_columns(name: 'Meta')).to be(false)
        expect(revisions(security)).to be_empty
        expect(security.changes).to eq('name' => %w[Facebook Meta])
      end
    end
  end

  describe 'with recording off' do
    it 'writes and records nothing while the process has recording off' do
      Recorder.enabled = false

      aggregate_failures do
        expect { security.recorder_update_columns(name: 'Meta') }.not_to change(Recorder::Revision, :count)
        expect(row(security).name).to eq('Meta')
        expect(security.saved_changes).to eq('name' => %w[Facebook Meta])
      end
    end

    it 'writes, records nothing and checks no condition inside recorder_disabled!' do
      evaluated = []
      model = securities_model('Disabled') { recorder if: -> { evaluated << :if } }
      record = model.create!(name: 'Facebook', identifier: 'FB')
      evaluated.clear

      Class.new { include Recorder::Manager }.new.recorder_disabled! do
        expect { record.recorder_update_columns(name: 'Meta') }.not_to change(Recorder::Revision, :count)
      end

      aggregate_failures do
        expect(row(record).name).to eq('Meta')
        expect(evaluated).to be_empty
      end
    end
  end

  describe 'if: and unless:' do
    def update_columns_of(model)
      model.create!(name: 'Facebook', identifier: 'FB').tap { |record| record.recorder_update_columns(name: 'Meta') }
    end

    it 'records when an if: method returns true and not when it returns false' do
      listed = securities_model('Listed')
      listed.class_eval do
        recorder if: :listed?

        private

        def listed? = true
      end
      unlisted = securities_model('Unlisted')
      unlisted.class_eval do
        recorder if: :listed?

        def listed? = false
      end

      aggregate_failures do
        expect(revisions(update_columns_of(listed)).count).to eq(1)
        record = update_columns_of(unlisted)
        expect(revisions(record)).to be_empty
        expect(row(record).name).to eq('Meta')
      end
    end

    it 'checks them after the write, as on a save' do
      model = securities_model('Leaving') { recorder if: -> { name == 'Facebook' || name_previously_was == 'Facebook' } }
      record = update_columns_of(model)
      record.recorder_update_columns(name: 'Instagram')

      expect(revisions(record).map { |revision| revision.data['changes'] }).to eq(['name' => %w[Facebook Meta]])
    end

    it 'passes the record to a Proc that takes an argument' do
      received = []
      model = securities_model('Argued') { recorder if: ->(record) { received << record } }
      record = update_columns_of(model)

      expect(received).to eq([record, record])
    end

    it 'records nothing when unless: returns true' do
      imported = securities_model('Imported') { recorder unless: ->(record) { record.name == 'Meta' } }
      kept = securities_model('Kept') { recorder unless: -> { false } }

      aggregate_failures do
        expect(revisions(update_columns_of(imported))).to be_empty
        expect(revisions(update_columns_of(kept)).count).to eq(1)
      end
    end

    it 'records only when if: holds and unless: does not' do
      model = securities_model('Both') { recorder if: -> { true }, unless: -> { identifier == 'X' } }
      records = [%w[Facebook FB], %w[Facebook X]].map { |name, identifier| model.create!(name: name, identifier: identifier) }
      records.each { |record| record.recorder_update_columns(name: 'Meta') }

      expect(records.map { |record| revisions(record).count }).to eq([1, 0])
    end

    it 'rolls the write back when a condition raises' do
      model = securities_model('Misspelt') { recorder if: :listd? }
      record = model.find(security.id)

      aggregate_failures do
        expect { record.recorder_update_columns(name: 'Meta') }.to raise_error(NoMethodError, /listd\?/)
        expect(row(record).name).to eq('Facebook')
        expect(record.changes).to eq('name' => %w[Facebook Meta])
      end
    end
  end

  describe 'on a model that is not observed' do
    it 'writes without a revision when the hierarchy never called recorder' do
      model = securities_model('Undeclared')
      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect { record.recorder_update_columns(name: 'Meta') }.not_to change(Recorder::Revision, :count)
        expect(row(record).name).to eq('Meta')
        expect(record.saved_changes).to eq('name' => %w[Facebook Meta])
      end
    end

    it 'is not defined without Recorder::Observer' do
      expect(User.new).not_to respond_to(:recorder_update_columns)
    end
  end

  describe 'errors' do
    it 'raises for a new record, assigning nothing' do
      record = Security.new(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect { record.recorder_update_columns(name: 'Meta') }
          .to raise_error(ActiveRecord::ActiveRecordError, 'cannot update a new record')
        expect(record.name).to eq('Facebook')
      end
    end

    it 'raises for a destroyed record' do
      security.destroy!

      expect { security.recorder_update_columns(name: 'Meta') }
        .to raise_error(ActiveRecord::ActiveRecordError, 'cannot update a destroyed record')
    end

    it 'raises for a readonly record, assigning and writing nothing' do
      security.readonly!

      aggregate_failures do
        expect { security.recorder_update_columns(name: 'Meta') }
          .to raise_error(ActiveRecord::ReadOnlyRecord, 'Security is marked as readonly')
        expect(security.name).to eq('Facebook')
        expect(row(security).name).to eq('Facebook')
      end
    end

    # Rails 8.1's `update_columns` takes `touch:`; this takes attributes only.
    it 'raises for an attribute the model does not have, writing nothing' do
      aggregate_failures do
        expect { security.recorder_update_columns(name: 'Meta', touch: true) }
          .to raise_error(ActiveModel::MissingAttributeError, /touch/)
        expect(row(security).name).to eq('Facebook')
        expect(revisions(security)).to be_empty
      end
    end

    it 'raises for a readonly attribute, assigning and writing nothing' do
      model = securities_model('Frozen')
      model.class_eval do
        recorder
        attr_readonly :identifier
      end
      record = model.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect { record.recorder_update_columns(name: 'Meta', identifier: 'META') }
          .to raise_error(ActiveRecord::ActiveRecordError, 'identifier is marked as readonly')
        expect(record.changes).to eq({})
        expect(row(record).attributes).to include('name' => 'Facebook', 'identifier' => 'FB')
        expect(revisions(record)).to be_empty
      end
    end
  end
end
