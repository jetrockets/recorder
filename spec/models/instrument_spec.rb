# frozen_string_literal: true

require 'rails_helper'

# End-to-end cover for the per-model `recorder` options. `Data` was always
# correct in isolation, so these only mean anything alongside the `Tape` lookup
# specs -- but they are the shape the bug was reported in.
RSpec.describe Instrument do
  describe 'ignore:' do
    let!(:instrument) { described_class.create!(name: 'Facebook', identifier: 'FB') }

    it 'keeps the ignored attribute out of the revision' do
      attributes = instrument.revisions.order(:id).last.data['attributes']

      aggregate_failures do
        expect(attributes).not_to have_key('identifier')
        expect(attributes).to include('name' => 'Facebook')
      end
    end

    it 'records nothing when only ignored attributes changed' do
      # `updated_at` moves on every save and nothing excludes it by default, so
      # it has to be globally ignored for the changeset to come out empty.
      Recorder.config.ignore = %i[updated_at]

      expect { instrument.update!(identifier: 'META') }
        .not_to change(Recorder::Revision, :count)
    end

    it 'still records when a tracked attribute changed alongside' do
      expect { instrument.update!(name: 'Meta', identifier: 'META') }
        .to change(Recorder::Revision, :count).by(1)

      changes = instrument.revisions.order(:id).last.data['changes']
      aggregate_failures do
        expect(changes).to include('name' => %w[Facebook Meta])
        expect(changes).not_to have_key('identifier')
      end
    end

    it 'composes with the global config rather than replacing it' do
      Recorder.config.ignore = %i[created_at updated_at]

      instrument.update!(name: 'Meta')

      attributes = instrument.revisions.order(:id).last.data['attributes']
      aggregate_failures do
        expect(attributes.keys).not_to include('identifier', 'created_at', 'updated_at')
        expect(attributes).to include('name' => 'Meta')
      end
    end
  end

  describe 'STI subclasses' do
    it 'applies the parent declaration to a subclass that declares nothing' do
      bond = Bond.create!(name: 'Facebook', identifier: 'FB')

      expect(bond.revisions.order(:id).last.data['attributes']).not_to have_key('identifier')
    end

    it 'applies the subclass declaration when it overrides' do
      stock = Stock.create!(name: 'Facebook', identifier: 'FB')

      expect(stock.revisions.order(:id).last.data['attributes'].keys).to eq(['name'])
    end

    it 'reaches revisions written by a subclass through the association' do
      # Regression: revisions were written under the subclass name while the
      # polymorphic association looked them up under the base class name.
      bond = Bond.create!(name: 'Facebook', identifier: 'FB')

      expect(bond.revisions.count).to eq(1)
    end
  end
end
