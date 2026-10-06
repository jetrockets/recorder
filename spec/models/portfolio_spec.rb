# frozen_string_literal: true

require 'rails_helper'

# A collection named in `associations:` is skipped with a warning, and the save
# goes through.
RSpec.describe Portfolio do
  let(:log) { StringIO.new }
  let(:warning) { 'Recorder: `associations:` names the collection :holdings of Portfolio' }

  before { allow(described_class).to receive(:logger).and_return(Logger.new(log)) }

  it 'records a create without the collection, and logs a warning' do
    portfolio = described_class.create!(name: 'Growth', identifier: 'GR')

    aggregate_failures do
      expect(portfolio.revisions.last.data).not_to have_key('associations')
      expect(log.string).to include(warning)
    end
  end

  context 'with a saved record' do
    let!(:portfolio) { described_class.create!(name: 'Growth', identifier: 'GR') }

    before { log.truncate(0) }

    it 'records an update, logging nothing' do
      portfolio.update!(name: 'Value')

      aggregate_failures do
        expect(portfolio.revisions.count).to eq(2)
        expect(log.string).to be_empty
      end
    end

    it 'records a destroy without the collection, and logs a warning' do
      portfolio.destroy!

      aggregate_failures do
        expect(Recorder::Revision.find_by!(event: 'destroy').data).not_to have_key('associations')
        expect(log.string).to include(warning)
      end
    end
  end
end
