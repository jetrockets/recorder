# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recorder do
  describe '.version' do
    it 'returns the version as a `String`' do
      expect(described_class.version).to be_a(String)
    end

    it 'agrees with `Recorder::VERSION`' do
      expect(described_class.version).to eq(Recorder::VERSION)
    end
  end
end
