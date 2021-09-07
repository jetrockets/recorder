# frozen_string_literal: true

require 'spec_helper'

module Recorder
  RSpec.describe Config do
    describe '.instance' do
      it 'returns the singleton instance' do
        expect { described_class.instance }.not_to raise_error
      end
    end

    describe '.new' do
      it 'raises `NoMethodError`' do
        expect { described_class.new }.to raise_error(NoMethodError)
      end
    end

    describe '#ignore' do
      it 'is default to blank `Array`' do
        expect(described_class.instance.ignore).to eq([])
      end
    end

    describe '#ignore=' do
      it 'accepts configuration' do
        options = %i[created_at updated_at]

        described_class.instance.ignore = options

        expect(described_class.instance.ignore).to eq(options)
      end

      it 'wraps arguments with `Array`' do
        options = :created_at

        described_class.instance.ignore = options

        expect(described_class.instance.ignore).to be_an_instance_of(Array)
        expect(described_class.instance.ignore).to eq(Array.wrap(options))
      end
    end

    describe '#async' do
      it 'is default to false' do
        expect(described_class.instance.async).to eq(false)
      end
    end

    describe '#async=' do
      it 'accepts configuration' do
        described_class.instance.async = true

        expect(described_class.instance.async).to eq(true)
      end

      it 'coerces to boolean' do
        described_class.instance.async = 'true'

        expect(described_class.instance.async).to eq(true)
      end
    end

    describe '#sidekiq_options' do
      it 'is default to `Hash` with options' do
        options = {
          queue: 'recorder',
          retry: 10,
          backtrace: true
        }

        expect(described_class.instance.sidekiq_options).to be_an_instance_of(Hash)
        expect(described_class.instance.sidekiq_options).to eq(options)
      end

      it 'accepts configuration' do
        options = {
          queue: 'myqueue',
          retry: 5,
          backtrace: false
        }

        described_class.instance.sidekiq_options = options

        expect(described_class.instance.sidekiq_options).to be_an_instance_of(Hash)
        expect(described_class.instance.sidekiq_options).to eq(options)
      end
    end
  end
end
