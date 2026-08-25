# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape do
  # The wiring that bug 01 broke: options are declared on the class, and every
  # consumer reads them off the instance. `Data` was well covered and correct;
  # nothing covered the lookup that feeds it.
  describe '#recorder_options' do
    subject(:options) { described_class.new(item).send(:recorder_options) }

    context 'when the item declares options' do
      let(:item) { Instrument.new }

      it 'resolves them from the instance' do
        expect(options).to eq(ignore: %i[identifier])
      end
    end

    context 'when the item is an STI subclass declaring nothing' do
      let(:item) { Bond.new }

      it 'inherits the options of its parent' do
        expect(options).to eq(ignore: %i[identifier])
      end
    end

    context 'when the item is an STI subclass declaring its own options' do
      let(:item) { Stock.new }

      it 'prefers the subclass declaration' do
        expect(options).to eq(only: %i[name])
      end
    end

    context 'when a sibling overrides' do
      it 'does not leak the override back up to the parent' do
        expect(Instrument.recorder_options).to eq(ignore: %i[identifier])
      end
    end

    context 'when the item declares nothing at all' do
      let(:item) { Security.new }

      it 'is an empty hash' do
        expect(options).to eq({})
      end
    end

    context 'when the item does not include Observer' do
      let(:item) { Object.new }

      it 'is an empty hash' do
        expect(options).to eq({})
      end
    end

    context 'when the app overrides the reader as an instance method' do
      # The shape a consuming app's workaround for bug 01 actually takes. It has
      # to keep winning, or the fix silently breaks the apps that worked around
      # the bug.
      let(:item) do
        Instrument.new.tap do |instrument|
          def instrument.recorder_options = {only: %i[settle_days]}
        end
      end

      it 'prefers the override over the class-level declaration' do
        expect(options).to eq(only: %i[settle_days])
      end
    end
  end

  describe 'the async write path' do
    let(:worker) { class_double('Recorder::Sidekiq::RevisionsWorker', perform_in: nil) }

    # A throwaway model rather than a fixture: `.recorder` writes a
    # `class_attribute` and registers callbacks, neither of which the
    # per-example transaction rolls back.
    def build_model(options)
      klass = stub_const('AsyncInstrument', Class.new(ApplicationRecord) { self.table_name = 'securities' })
      klass.include(Recorder::Observer)
      klass.recorder(options)
      klass
    end

    before do
      allow(Recorder).to receive_messages(sidekiq_worker: worker, sidekiq_available?: true)
    end

    it 'enqueues instead of writing inline when the model asked for async' do
      model = build_model(ignore: %i[identifier], async: true)

      expect { model.create!(name: 'Facebook', identifier: 'FB') }
        .not_to change(Recorder::Revision, :count)

      expect(worker).to have_received(:perform_in) do |delay, params|
        expect(delay).to eq(2.seconds)
        expect(params['item_type']).to eq('AsyncInstrument')
        expect(params['event']).to eq('create')
        expect(JSON.parse(params['data'])['attributes']).not_to have_key('identifier')
      end
    end

    it 'writes inline when the model did not ask for async' do
      model = build_model(ignore: %i[identifier])

      expect { model.create!(name: 'Facebook', identifier: 'FB') }
        .to change(Recorder::Revision, :count).by(1)

      expect(worker).not_to have_received(:perform_in)
    end
  end
end
