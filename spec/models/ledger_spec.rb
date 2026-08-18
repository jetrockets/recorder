# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ledger do
  describe 'associations:' do
    it 'records the association alongside the item' do
      guard = described_class.create!(name: 'Guard', identifier: 'GD')
      ledger = described_class.create!(name: 'Facebook', identifier: 'FB', guard: guard)

      associations = ledger.revisions.order(:id).last.data['associations']

      expect(associations['guard']['attributes']).to eq('name' => 'Guard')
    end
  end
end
