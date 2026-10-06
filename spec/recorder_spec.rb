# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder do
  describe '.version' do
    it 'returns the version as a `String`' do
      expect(described_class.version).to be_a(String)
    end

    it 'agrees with `Recorder::VERSION`' do
      expect(described_class.version).to eq(Recorder::VERSION)
    end
  end

  describe '.deprecator' do
    it 'names Recorder in its warnings' do
      expect(described_class.deprecator.gem_name).to eq('Recorder')
    end

    it 'is registered with the application, where Rails keeps a registry' do
      skip 'Rails::Application#deprecators arrived in Rails 7.1' unless Rails.application.respond_to?(:deprecators)

      expect(Rails.application.deprecators[:recorder]).to equal(described_class.deprecator)
    end
  end

  describe '.recording?' do
    it 'is true by default' do
      expect(described_class.recording?).to be(true)
    end

    it 'is false while the process has recording off' do
      described_class.enabled = false

      expect(described_class.recording?).to be(false)
    end

    it 'is false while the request has recording off' do
      described_class.store.recorder_disabled!

      expect(described_class.recording?).to be(false)
    end

    it 'is false in another thread while the process has recording off' do
      described_class.enabled = false

      expect(Thread.new { described_class.recording? }.value).to be(false)
    end

    it 'stays true in another thread while one request has recording off' do
      described_class.store.recorder_disabled!

      expect(Thread.new { described_class.recording? }.value).to be(true)
    end
  end

  describe '.info=' do
    it 'keeps the request context for the revisions that follow' do
      described_class.info = {user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1)}

      expect(described_class.store.params).to include(user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1))
    end

    it 'stores a string key as the symbol it replaces' do
      described_class.info = {user_id: 1}
      described_class.info = {'user_id' => 2}

      expect(described_class.store.params).to eq(user_id: 2)
    end

    %i[id item_type item_id event data created_at].each do |column|
      it "refuses #{column}, which Recorder writes itself" do
        expect { described_class.info = {column => 'anything'} }
          .to raise_error(ArgumentError, /cannot set columns Recorder writes itself: #{column}\./)
      end
    end

    it 'refuses a reserved column given as a string key' do
      expect { described_class.info = {'created_at' => Time.current} }
        .to raise_error(ArgumentError, /created_at/)
    end

    it 'keeps none of the hash it refuses' do
      expect { described_class.info = {user_id: 1, created_at: Time.current} }.to raise_error(ArgumentError)

      expect(described_class.store.params).to be_empty
    end
  end
end
