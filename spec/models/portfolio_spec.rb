# frozen_string_literal: true

require 'rails_helper'

# A collection named in `associations:` fails the save instead of being dropped.
RSpec.describe Portfolio do
  include Recorder::Manager

  let(:message) { /`associations:` names the collection :holdings of Portfolio/ }

  it 'fails a create, leaving neither the record nor a revision' do
    aggregate_failures do
      expect { described_class.create!(name: 'Growth', identifier: 'GR') }.to raise_error(ArgumentError, message)
      expect(described_class.count).to eq(0)
      expect(Recorder::Revision.count).to eq(0)
    end
  end

  context 'with a record saved while recording was off' do
    let!(:portfolio) { recorder_disabled! { described_class.create!(name: 'Growth', identifier: 'GR') } }

    it 'fails an update, leaving the record as it was' do
      aggregate_failures do
        expect { portfolio.update!(name: 'Value') }.to raise_error(ArgumentError, message)
        expect(portfolio.reload.name).to eq('Growth')
        expect(Recorder::Revision.count).to eq(0)
      end
    end

    it 'fails a destroy, leaving the record in place' do
      aggregate_failures do
        expect { portfolio.destroy! }.to raise_error(ArgumentError, message)
        expect(described_class.exists?(portfolio.id)).to be(true)
        expect(Recorder::Revision.count).to eq(0)
      end
    end
  end
end
