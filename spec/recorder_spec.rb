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

  describe '.info=' do
    it 'keeps the request context for the revisions that follow' do
      described_class.info = {user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1)}

      expect(described_class.store.params).to include(user_id: 1, ip: '127.0.0.1', action_date: Date.new(2020, 1, 1))
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
