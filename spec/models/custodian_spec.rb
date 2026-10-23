# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custodian do
  describe 'associations:' do
    it 'records a has_one child that Rails saves after the create revision' do
      custodian = described_class.create!(name: 'Custodian', identifier: 'CU', ward: Security.new(name: 'Ward', identifier: 'WD'))

      expect(custodian.revisions.order(:id).last.data['associations']).to eq('ward' => {'attributes' => {'name' => 'Ward'}})
    end
  end
end
