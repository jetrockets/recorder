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
          expect(changeset.keys).to be_empty
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

    # `#previous` and `#next` rebuild the record by assigning values onto a `dup`.
    describe '#previous and #next' do
      let(:item) { Security.new(name: 'Meta', pricing_factor: BigDecimal('2.25')) }
      # String keys and string values, as `data['changes']` returns them.
      let(:changes) do
        {'name' => %w[Facebook Meta], 'pricing_factor' => ['1.5', '2.25']}
      end

      it 'casts a value back to the attribute type' do
        changeset = described_class.new(item, changes)

        aggregate_failures do
          expect(changeset.previous(:pricing_factor)).to eq(BigDecimal('1.5'))
          expect(changeset.previous(:pricing_factor)).to be_a(BigDecimal)
        end
      end

      it 'returns the value before the change' do
        changeset = described_class.new(item, changes)

        expect(changeset.previous(:name)).to eq('Facebook')
      end

      it 'returns the value after the change' do
        changeset = described_class.new(item, changes)

        expect(changeset.next(:name)).to eq('Meta')
      end

      it 'leaves the item itself untouched' do
        changeset = described_class.new(item, changes)
        changeset.previous(:name)

        expect(item.name).to eq('Meta')
      end
    end
  end
end
