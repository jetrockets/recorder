# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape do
  # `item_type` is the model's polymorphic name, as Active Record writes it for
  # any polymorphic association.
  describe 'item_type' do
    def item_type_of(record)
      Recorder::Revision.where(item_id: record.id).last.item_type
    end

    it 'is the class name of a model without STI' do
      expect(item_type_of(Security.create!(name: 'Facebook', identifier: 'FB'))).to eq('Security')
    end

    it 'is the base class name of an STI subclass' do
      expect(item_type_of(Bond.create!(name: 'Treasury', identifier: 'UST'))).to eq('Instrument')
    end

    it 'is the base class name when only the subclass records' do
      parent = stub_const('Unobserved', Class.new(ApplicationRecord) { self.table_name = 'securities' })
      child = stub_const('Observed', Class.new(parent) { include Recorder::Observer })
      child.recorder
      record = child.create!(name: 'Facebook', identifier: 'FB')

      aggregate_failures do
        expect(item_type_of(record)).to eq('Unobserved')
        expect(record.revisions.count).to eq(1)
      end
    end
  end

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

    context 'when a subclass defines recorder_options as a private method' do
      let(:item) do
        stub_const('PrivateNote', Class.new(Instrument) do
          private

          def recorder_options
            {only: %i[name]}
          end
        end).new
      end

      it 'uses it' do
        expect(options).to eq(only: %i[name])
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
