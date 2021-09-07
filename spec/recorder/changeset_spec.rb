# frozen_string_literal: true

require 'rails_helper'

module Recorder
  RSpec.describe Changeset do
    describe '#initialize' do
      let(:item) { Security.new }
      let(:changes) { {} }

      it 'correctly sets instance variables' do
        changeset = described_class.new(item, changes)

        expect(changeset.instance_variable_get(:@item)).to eql(item)
        expect(changeset.instance_variable_get(:@changes)).to eql(changes)
      end

      it 'raises `ArgumentError` for `nil` changes' do
        expect { described_class.new(item, nil) }.to raise_error(ArgumentError)
      end

      it 'raises `ArgumentError` for changes with odd number of arguments that are not `Hash`' do
        expect { described_class.new(item, 1) }.to raise_error(ArgumentError)
      end
    end

    describe '#keys' do
      let(:item) { Security.new }

      describe 'blank changes' do
        let(:changes) { {} }

        it 'returns an empty `Array`' do
          changeset = described_class.new(item, changes)
          expect(changeset.keys).to match_array([])
        end
      end

      describe 'actual changes' do
        let(:changes) { {name: %w[Facebook Yandex], identifier: %w[FB YNDX]} }

        it 'returns keys' do
          changeset = described_class.new(item, changes)
          expect(changeset.keys).to match_array(changes.keys)
        end
      end
    end

    describe '#human_attribute_name' do
      let(:changes) { {name: %w[Facebook Yandex], identifier: %w[FB YNDX]} }

      describe 'not decorated object' do
        let(:item) { Security.new }

        it 'returns human attribute name for item' do
          changeset = described_class.new(item, changes)
          expect(changeset.human_attribute_name(:identifier)).to eq(Security.human_attribute_name(:identifier))
        end
      end
    end
  end
end
