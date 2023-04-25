# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape::Data do
  subject { described_class.new(item) }

  let(:item) do
    Security.new(type: 'type', name: 'name', identifier: 'identifier')
  end

  describe '#data_for' do
    let(:data_for) { subject.data_for(event, {only: %i[type name]}) }

    context 'when event is :create' do
      let(:event) { :create }

      it 'returns data for :create event' do
        expect(data_for).to eq(attributes: {type: 'type', name: 'name'})
      end
    end

    context 'when event is :update' do
      let(:event) { :update }

      context 'and the item has changed' do
        before do
          allow(item).to receive(:saved_changes).and_return({name: 'security', identifier: 'id'})
        end

        it 'returns data for :update event' do
          expect(data_for).to eq(
            attributes: {type: 'type', name: 'name'},
            changes: {name: 'security'}
          )
        end
      end

      context 'and the item has not changed' do
        it 'returns an empty hash' do
          expect(data_for).to eq({})
        end
      end
    end

    context 'when event is :destroy' do
      let(:event) { :destroy }

      it 'returns data for :destroy event' do
        expect(data_for).to eq(attributes: {type: 'type', name: 'name'})
      end
    end
  end

  describe '#attributes_for' do
    let(:attributes_for) { subject.attributes_for(:create, options) }

    context 'when options[:only] is present' do
      let(:options) { {only: %i[type name invalid]} }

      it 'returns only attributes included in :only' do
        expect(attributes_for).to eq(
          attributes: {type: 'type', name: 'name'}
        )
      end
    end

    context 'when options[:ignore] is present' do
      let(:options) { {ignore: %i[type name invalid]} }

      it 'returns all attributes expect the ones that are included in :ignore' do
        expect(attributes_for).to eq(
          attributes: {
            id: nil,
            identifier: 'identifier',
            settle_days: 3,
            pricing_factor: 1.0,
            created_at: nil,
            updated_at: nil
          }
        )
      end
    end

    context 'when options does not contain :only or :ignore' do
      let(:options) { {} }

      it 'returns all attributes' do
        expect(attributes_for).to eq(
          attributes: {
            id: nil,
            type: 'type',
            name: 'name',
            identifier: 'identifier',
            settle_days: 3,
            pricing_factor: 1.0,
            created_at: nil,
            updated_at: nil
          }
        )
      end
    end
  end

  describe '#changes_for' do
    let(:changes_for) { subject.changes_for(:update, options) }

    context 'when the item has changed' do
      before do
        allow(item).to receive(:saved_changes).and_return({name: 'security', identifier: 'id'})
      end

      context 'and options[:only] is present' do
        let(:options) { {only: %i[type name invalid]} }

        it 'returns only attributes included in :only' do
          expect(changes_for).to eq(changes: {name: 'security'})
        end
      end

      context 'and options[:ignore] is present' do
        let(:options) { {ignore: %i[type name invalid]} }

        it 'returns all attributes expect the ones that are included in :ignore' do
          expect(changes_for).to eq(changes: {identifier: 'id'})
        end
      end

      context 'when options does not contain :only or :ignore' do
        let(:options) { {} }

        it 'returns all attributes' do
          expect(changes_for).to eq(changes: {name: 'security', identifier: 'id'})
        end
      end
    end

    context 'when the item has not changed' do
      let(:options) { {} }

      it 'returns an empty hash' do
        expect(changes_for).to eq({})
      end
    end
  end

  describe '#associations_for' do
    let(:associations_for) { subject.associations_for(:create, options) }

    context 'when options[:associations] is blank' do
      let(:options) { {} }

      it 'returns an empty hash' do
        expect(associations_for).to eq({})
      end
    end
  end
end
