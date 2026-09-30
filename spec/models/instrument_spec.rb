# frozen_string_literal: true

require 'rails_helper'

# The per-model `recorder` options, from declaration to the stored revision.
RSpec.describe Instrument do
  let!(:instrument) { described_class.create!(name: 'Facebook', identifier: 'FB') }

  def last_revision(item = instrument)
    item.revisions.order(:id).last
  end

  describe 'ignore:' do
    it 'keeps the ignored attributes out of the snapshot' do
      attributes = last_revision.data['attributes']

      aggregate_failures do
        expect(attributes.keys).not_to include('identifier', 'updated_at')
        expect(attributes).to include('name' => 'Facebook')
      end
    end

    it 'records nothing when only ignored attributes changed' do
      expect { instrument.update!(identifier: 'META') }
        .not_to change(Recorder::Revision, :count)
    end

    it 'keeps the ignored attributes out of the changes' do
      instrument.update!(name: 'Meta', identifier: 'META')

      expect(last_revision.data['changes']).to eq('name' => %w[Facebook Meta])
    end

    it 'keeps the ignored attributes out of a destroy revision' do
      instrument.destroy!

      revision = last_revision
      aggregate_failures do
        expect(revision.event).to eq('destroy')
        expect(revision.data['attributes'].keys).not_to include('identifier', 'updated_at')
      end
    end

    it 'replaces the global ignore list rather than adding to it' do
      Recorder.config.ignore = %i[settle_days]

      security = Security.create!(name: 'Facebook', identifier: 'FB')
      instrument.update!(name: 'Meta')

      aggregate_failures do
        expect(last_revision(security).data['attributes']).not_to have_key('settle_days')
        expect(last_revision.data['attributes']).to have_key('settle_days')
      end
    end
  end

  describe 'only:' do
    # A throwaway model: `.recorder` registers callbacks, which outlive an example.
    let(:model) do
      stub_const('NamedInstrument', Class.new(ApplicationRecord) { self.table_name = 'securities' }).tap do |model|
        model.include(Recorder::Observer)
        model.recorder only: %i[name]
      end
    end
    let!(:named) { model.create!(name: 'Facebook', identifier: 'FB') }

    it 'keeps every other attribute out of the snapshot' do
      expect(last_revision(named).data['attributes']).to eq('name' => 'Facebook')
    end

    it 'records nothing when only other attributes changed' do
      expect { named.update!(identifier: 'META') }
        .not_to change(Recorder::Revision, :count)
    end

    it 'records a change to a listed attribute' do
      named.update!(name: 'Meta', identifier: 'META')

      expect(last_revision(named).data['changes']).to eq('name' => %w[Facebook Meta])
    end
  end

  describe 'changes:' do
    it 'merges the custom entries into the revision' do
      expect(last_revision.data['changes']).to include('ticker' => [nil, 'FB'])
    end
  end

  describe 'associations:' do
    it 'records the association alongside the item' do
      owned = described_class.create!(name: 'Instagram', identifier: 'IG', guard: instrument)

      expect(last_revision(owned).data['associations']['guard']['attributes']).to eq('name' => 'Facebook')
    end
  end
end
