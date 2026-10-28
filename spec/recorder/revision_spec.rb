# frozen_string_literal: true

require 'rails_helper'

module Recorder
  RSpec.describe Revision do
    let(:user) { User.create!(name: 'Igor') }

    # Were `belongs_to :user` required, every save without a user would raise
    # `RevisionNotSaved`. Were `belongs_to :item` required, so would every
    # `destroy`, since its revision is written after the row is deleted.
    describe 'recording without a user' do
      context 'when no user is set' do
        it 'records a revision' do
          expect { Security.create!(name: 'Facebook', identifier: 'FB') }
            .to change(described_class, :count).by(1)
        end

        it 'leaves the user blank' do
          Security.create!(name: 'Facebook', identifier: 'FB')

          expect(described_class.order(:id).last.user_id).to be_nil
        end
      end

      context 'when the user no longer exists' do
        before { Recorder.info = {user_id: 999_999} }

        it 'records a revision' do
          expect { Security.create!(name: 'Facebook', identifier: 'FB') }
            .to change(described_class, :count).by(1)
        end
      end

      it 'declares the `user` association optional' do
        expect(described_class.reflect_on_association(:user).options[:optional]).to be(true)
      end

      it 'runs no presence validation on the `user` association' do
        expect(described_class.validators_on(:user)).to be_empty
      end

      it 'considers a revision without a user valid' do
        revision = described_class.new(
          item_type: 'Security', item_id: 1, event: 'create',
          action_date: Date.today, data: {attributes: {}}
        )

        expect(revision).to be_valid
      end
    end

    describe 'recording an item that no longer exists' do
      it 'declares the `item` association optional' do
        expect(described_class.reflect_on_association(:item).options[:optional]).to be(true)
      end

      it 'runs no presence validation on the `item` association' do
        expect(described_class.validators_on(:item)).to be_empty
      end

      it 'considers a revision of a deleted item valid' do
        security = Security.create!(name: 'Facebook', identifier: 'FB')
        security.destroy!

        revision = described_class.new(
          item_type: 'Security', item_id: security.id, event: 'destroy',
          action_date: Date.today, data: {attributes: {}}
        )

        expect(revision).to be_valid
      end
    end

    describe '.ordered_by_created_at' do
      let(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }

      def events_in_order
        security.revisions.ordered_by_created_at.pluck(:event)
      end

      it 'returns the newest revision first' do
        security.update!(name: 'Meta')
        security.revisions.where(event: 'create').update_all(created_at: 1.day.ago)

        expect(events_in_order).to eq(%w[update create])
      end

      it 'returns revisions written in the same instant newest first' do
        security.update!(name: 'Meta')
        security.revisions.update_all(created_at: Time.current)

        expect(events_in_order).to eq(%w[update create])
      end
    end

    # The changeset is rebuilt from values that have been through the `jsonb`
    # column, so every attribute comes back out as a string and is cast again.
    describe '#item_changeset' do
      subject(:changeset) { revision.item_changeset }

      let(:security) do
        Security.create!(name: 'Facebook', identifier: 'FB', pricing_factor: BigDecimal('1.5'))
      end
      let(:revision) do
        security.update!(name: 'Meta', pricing_factor: BigDecimal('2.25'))
        described_class.order(:id).last
      end

      before { Recorder.info = {user_id: user.id} }

      it 'returns the values a string attribute held before and after the change' do
        aggregate_failures do
          expect(changeset.previous(:name)).to eq('Facebook')
          expect(changeset.next(:name)).to eq('Meta')
        end
      end

      it 'returns a decimal attribute as a BigDecimal' do
        aggregate_failures do
          expect(changeset.previous(:pricing_factor)).to eq(BigDecimal('1.5'))
          expect(changeset.next(:pricing_factor)).to eq(BigDecimal('2.25'))
        end
      end

      it 'returns the value a datetime attribute held before the change' do
        before_update = security.updated_at

        expect(changeset.previous(:updated_at)).to be_within(0.001).of(before_update)
      end

      it 'returns a datetime attribute in the application time zone' do
        expect(changeset.previous(:updated_at)).to be_a(ActiveSupport::TimeWithZone)
      end
    end

    describe '#item_changeset edge cases' do
      let(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }
      let(:revision) do
        security.update!(name: 'Meta')
        described_class.order(:id).last
      end

      it 'builds the changeset once' do
        expect(revision.item_changeset).to equal(revision.item_changeset)
      end

      it 'is nil when the item no longer exists' do
        revision
        security.destroy!

        expect(described_class.find(revision.id).item_changeset).to be_nil
      end

      it 'is nil when the revision holds no changes' do
        revision = described_class.create!(
          item: security, event: 'create', action_date: Date.current, data: {attributes: {name: 'Facebook'}}
        )

        expect(revision.item_changeset).to be_nil
      end
    end

    # The changeset class is `<model>Changeset` when defined, or what the model's
    # `recorder_changeset_class` answers, or `Recorder::Changeset`.
    describe 'changeset class' do
      let(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }
      let(:revision) do
        security.update!(name: 'Meta')
        described_class.order(:id).last
      end

      it 'defaults to Recorder::Changeset' do
        expect(revision.item_changeset).to be_an_instance_of(Recorder::Changeset)
      end

      it 'is the class named after the model when one is defined' do
        changeset_class = stub_const('SecurityChangeset', Class.new(Recorder::Changeset))

        expect(revision.item_changeset).to be_an_instance_of(changeset_class)
      end

      it 'is what the model answers from recorder_changeset_class' do
        changeset_class = stub_const('LedgerChanges', Class.new(Recorder::Changeset))
        model = stub_const('Ledger', Class.new(ApplicationRecord) do
          include Recorder::Observer

          self.table_name = 'securities'

          recorder

          def self.recorder_changeset_class
            LedgerChanges
          end
        end)
        ledger = model.create!(name: 'Facebook', identifier: 'FB')
        ledger.update!(name: 'Meta')

        expect(described_class.order(:id).last.item_changeset).to be_an_instance_of(changeset_class)
      end

      # A Draper decorator answers `decorated?` and holds the model as `source`.
      context 'when the item is decorated' do
        let(:decorator) do
          Class.new do
            attr_reader :source

            def initialize(source)
              @source = source
            end

            def decorated?
              true
            end
          end
        end

        before do
          stub_const('Draper', Module.new)
          allow(revision).to receive(:item).and_return(decorator.new(security))
        end

        it 'resolves the class from the decorated model' do
          changeset_class = stub_const('SecurityChangeset', Class.new(Recorder::Changeset))

          expect(revision.item_changeset).to be_an_instance_of(changeset_class)
        end
      end
    end

    # An association entry may or may not hold `changes`.
    describe 'association readers' do
      let(:guard) { Instrument.create!(name: 'Meta', identifier: 'META') }
      let(:instrument) { Instrument.create!(name: 'Instagram', identifier: 'IG', guard: guard) }
      let(:revision) do
        described_class.create!(
          item: instrument, event: 'update', action_date: Date.current,
          data: {attributes: {name: 'Instagram'}, associations: associations}
        )
      end

      context 'when an association carries changes' do
        let(:associations) do
          {
            guard: {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}},
            owner: {attributes: {name: 'Owner'}}
          }
        end

        it 'lists only that association as changed' do
          expect(revision.changed_associations).to eq(['guard'])
        end

        it 'returns its changeset' do
          changeset = revision.association_changeset('guard')

          aggregate_failures do
            expect(changeset.previous(:name)).to eq('Facebook')
            expect(changeset.next(:name)).to eq('Meta')
          end
        end
      end

      context 'when an association carries only its snapshot' do
        let(:associations) { {guard: {attributes: {name: 'Meta'}}} }

        it 'lists no changed associations' do
          expect(revision.changed_associations).to eq([])
        end

        it 'returns no changeset' do
          expect(revision.association_changeset('guard')).to be_nil
        end
      end

      context 'when the revision has no associations' do
        let(:revision) do
          described_class.create!(item: instrument, event: 'update', action_date: Date.current, data: {attributes: {}})
        end

        it 'lists no changed associations' do
          expect(revision.changed_associations).to eq([])
        end

        it 'returns no changeset' do
          expect(revision.association_changeset('guard')).to be_nil
        end
      end

      context 'when the associated record is no longer set' do
        let(:associations) { {guard: {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}}} }

        before do
          revision
          instrument.update!(guard: nil)
        end

        it 'returns no changeset' do
          expect(described_class.find(revision.id).association_changeset('guard')).to be_nil
        end
      end

      context 'when the item no longer exists' do
        let(:associations) { {guard: {attributes: {name: 'Meta'}, changes: {name: %w[Facebook Meta]}}} }

        before do
          revision
          instrument.destroy!
        end

        it 'returns no changeset' do
          expect(described_class.find(revision.id).association_changeset('guard')).to be_nil
        end
      end
    end
  end
end
