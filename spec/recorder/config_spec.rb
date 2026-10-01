# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recorder::Config do
  before do
    described_class.instance.reset
  end

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
end
