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

  describe '#revision_class' do
    it 'is nil by default' do
      expect(described_class.instance.revision_class).to be_nil
    end

    it 'is nil again after #reset' do
      described_class.instance.revision_class = 'AppRevision'
      described_class.instance.reset

      expect(described_class.instance.revision_class).to be_nil
    end
  end

  describe '#revision_class=' do
    it 'keeps a frozen copy of the name' do
      name = +'AppRevision'
      described_class.instance.revision_class = name

      aggregate_failures do
        expect(described_class.instance.revision_class).to eq('AppRevision')
        expect(described_class.instance.revision_class).to be_frozen
        expect(name).not_to be_frozen
      end
    end

    it 'accepts nil' do
      described_class.instance.revision_class = 'AppRevision'
      described_class.instance.revision_class = nil

      expect(described_class.instance.revision_class).to be_nil
    end

    it 'raises for a class, asking for its name' do
      expect { described_class.instance.revision_class = Recorder::Revision }
        .to raise_error(ArgumentError, /expects a class name as a String.*Pass the name, not the class/)
    end

    [:AppRevision, '', ' '].each do |value|
      it "raises for #{value.inspect}" do
        expect { described_class.instance.revision_class = value }.to raise_error(ArgumentError, /class name/)
      end
    end
  end
end
