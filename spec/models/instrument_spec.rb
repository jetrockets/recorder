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
