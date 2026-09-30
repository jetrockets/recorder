# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape do
  # Options are declared on the class and read off the record.
  describe '#recorder_options' do
    subject(:options) { described_class.new(item).send(:recorder_options) }

    context 'when the model declares options' do
      let(:item) { Instrument.new }

      it 'resolves them' do
        expect(options).to eq(Instrument.recorder_options)
      end

      it 'carries what was passed to .recorder' do
        expect(options).to include(ignore: %i[identifier updated_at], changes: :ticker_change)
      end
    end

    context 'when the model calls .recorder without options' do
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

    context 'when the record defines recorder_options itself' do
      let(:item) do
        Instrument.new.tap do |instrument|
          def instrument.recorder_options
            {only: %i[settle_days]}
          end
        end
      end

      it 'prefers the record over the class-level declaration' do
        expect(options).to eq(only: %i[settle_days])
      end
    end

    context 'when the model defines recorder_options before including Observer' do
      let(:model) do
        stub_const('EarlyInstrument', Class.new(ApplicationRecord) do
          self.table_name = 'securities'

          def recorder_options
            {only: %i[name]}
          end
        end)
      end
      let(:item) { model.new }

      before do
        model.include(Recorder::Observer)
        model.recorder ignore: %i[name]
      end

      it 'prefers the instance method' do
        expect(options).to eq(only: %i[name])
      end
    end
  end
end
