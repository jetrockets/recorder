# frozen_string_literal: true

require 'rails_helper'

# An STI subclass records under the options its parent declared.
RSpec.describe Bond do
  let!(:bond) { described_class.create!(name: 'Treasury', identifier: 'UST') }

  def revisions
    Recorder::Revision.where(item_id: bond.id).order(:id)
  end

  it 'inherits the options declared on Instrument' do
    expect(described_class.recorder_options).to equal(Instrument.recorder_options)
  end

  it 'keeps the ignored attributes out of the snapshot' do
    expect(revisions.last.data['attributes'].keys).not_to include('identifier', 'updated_at')
  end

  it 'records nothing when only ignored attributes changed' do
    expect { bond.update!(identifier: 'T') }.not_to change(Recorder::Revision, :count)
  end

  it 'writes one revision per event' do
    bond.update!(name: 'Treasury Note')
    bond.destroy!

    expect(revisions.pluck(:event)).to eq(%w[create update destroy])
  end
end
