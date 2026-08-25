# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recorder::Manager do
  subject(:manager) { Class.new { include Recorder::Manager }.new }

  before do
    RequestStore.clear!
    Recorder.instance_variable_set(:@store, nil)
  end

  describe '#recorder_disabled!' do
    context 'without a block' do
      it 'leaves recording disabled' do
        manager.recorder_disabled!

        expect(Recorder.store.recorder_enabled?).to be(false)
      end
    end

    context 'with a block' do
      it 'disables recording for the duration of the block' do
        observed = nil

        manager.recorder_disabled! { observed = Recorder.store.recorder_enabled? }

        expect(observed).to be(false)
      end

      it 're-enables recording afterwards' do
        manager.recorder_disabled! { nil }

        expect(Recorder.store.recorder_enabled?).to be(true)
      end

      it 're-enables recording when the block raises' do
        expect { manager.recorder_disabled! { raise 'boom' } }.to raise_error('boom')

        expect(Recorder.store.recorder_enabled?).to be(true)
      end

      it 'lets the exception propagate' do
        expect { manager.recorder_disabled! { raise ArgumentError } }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#recorder_enabled!' do
    it 'enables recording' do
      manager.recorder_disabled!
      manager.recorder_enabled!

      expect(Recorder.store.recorder_enabled?).to be(true)
    end
  end
end
