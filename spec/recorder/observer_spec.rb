# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Observer do
  # Sidekiq is not a dependency of this gem, so the worker is stubbed rather
  # than installed -- adding it as a dev dependency would contradict the gem's
  # "Sidekiq is optional" posture.
  def build_model(name)
    # Named before `include`: the polymorphic `has_many` that `Observer`
    # installs derives its inverse from the class name, and an anonymous class
    # has none.
    klass = stub_const(name, Class.new(ApplicationRecord) { self.table_name = 'securities' })
    klass.include(described_class)
    klass
  end

  describe '.recorder with async: true' do
    context 'when Sidekiq is absent' do
      it 'raises at declaration time rather than on the first save' do
        model = build_model('AsyncSecurity')

        expect { model.recorder(async: true) }
          .to raise_error(Recorder::SidekiqNotAvailable, /AsyncSecurity.*Sidekiq is not loaded/m)
      end
    end

    context 'when Sidekiq is present' do
      before { allow(Recorder).to receive(:sidekiq_available?).and_return(true) }

      it 'accepts the declaration' do
        model = build_model('AsyncSecurity')

        expect { model.recorder(async: true) }.not_to raise_error
        expect(model.recorder_options).to eq(async: true)
      end
    end
  end

  describe '.recorder without async' do
    it 'is unaffected by Sidekiq being absent' do
      model = build_model('SyncSecurity')

      expect { model.recorder(ignore: %i[identifier]) }.not_to raise_error
    end
  end

  describe '.recorder_options' do
    it 'defaults to an empty hash for a model that never called .recorder' do
      expect(build_model('BareSecurity').recorder_options).to eq({})
    end
  end
end
