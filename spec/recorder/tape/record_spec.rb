# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape::Record do
  # What matters for the supported range is the payload: Sidekiq 7 raises on job
  # arguments that are not JSON native, and a Rails 7.1+ app is running Sidekiq 7
  # or 8. `spec/support/sidekiq_stand_in.rb` loads the worker class so the double
  # below is verified against it.
  describe 'recording asynchronously' do
    let(:user) { User.create!(name: 'Igor') }
    let(:worker) { class_double(Recorder::Sidekiq::RevisionsWorker) }
    let(:enqueued) { [] }

    before do
      stub_const('Recorder::Sidekiq::RevisionsWorker', worker)
      allow(worker).to receive(:perform_in) { |delay, params| enqueued << [delay, params] }

      Recorder.config.async = true
      Recorder.info = {user_id: user.id}
    end

    # Mirrors Sidekiq's own strict-args check: JSON natives only, Hash keys String.
    def json_native?(value)
      case value
      when String, Integer, Float, TrueClass, FalseClass, NilClass then true
      when Array then value.all? { |v| json_native?(v) }
      when Hash then value.all? { |k, v| k.is_a?(String) && json_native?(v) }
      else false
      end
    end

    def record_and_capture
      Security.create!(name: 'Facebook', identifier: 'FB')
      enqueued.last
    end

    it 'enqueues instead of writing a revision row' do
      expect { Security.create!(name: 'Facebook', identifier: 'FB') }
        .not_to change(Recorder::Revision, :count)

      expect(enqueued.size).to eq(1)
    end

    # Sidekiq coerces perform_in's interval itself; only *args face strict args.
    it 'enqueues with the default two second delay' do
      expect(record_and_capture.first.to_f).to eq(2.0)
    end

    # `Tape` reads the delay off the options it is handed. Per-model `recorder`
    # options do not reach it, so `record` is called directly here.
    it 'enqueues with the delay the options carry' do
      params = {event: 'create', item_type: 'Security', item_id: 1, data: {}}

      Recorder::Tape.record(params, delay: 10.seconds)

      expect(enqueued.last.first.to_f).to eq(10.0)
    end

    it 'passes the data column pre-serialized as a JSON string' do
      expect(record_and_capture.last['data']).to be_a(String)
    end

    it 'passes the action date as a string a date column accepts' do
      action_date = record_and_capture.last['action_date']

      aggregate_failures do
        expect(action_date).to be_a(String)
        expect(Date.parse(action_date)).to eq(Date.today)
      end
    end

    it 'passes only JSON-native arguments' do
      params = record_and_capture.last

      expect(json_native?(params)).to be(true), "params is #{params.inspect}"
    end

    context 'when the controller concern has supplied meta' do
      before { Recorder.meta = {source: 'web', request: {id: 'abc123'}} }

      it 'passes only JSON-native arguments' do
        params = record_and_capture.last

        expect(json_native?(params)).to be(true), "params is #{params.inspect}"
      end
    end

    context 'when meta carries values that are not JSON native' do
      before { Recorder.meta = {status: :active, recorded_on: Date.new(2026, 8, 25)} }

      it 'passes only JSON-native arguments' do
        params = record_and_capture.last

        expect(json_native?(params)).to be(true), "params is #{params.inspect}"
      end
    end

    context 'when the event is an update' do
      before { Recorder.meta = {status: :active, recorded_on: Date.new(2026, 8, 25)} }

      let!(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }

      it 'passes only JSON-native arguments' do
        security.update!(name: 'Meta')
        params = enqueued.last.last

        aggregate_failures do
          expect(params['event']).to eq('update')
          expect(json_native?(params)).to be(true), "params is #{params.inspect}"
        end
      end
    end

    context 'when the event is a destroy' do
      before { Recorder.meta = {status: :active, recorded_on: Date.new(2026, 8, 25)} }

      let!(:security) { Security.create!(name: 'Facebook', identifier: 'FB') }

      it 'passes only JSON-native arguments' do
        security.destroy!
        params = enqueued.last.last

        aggregate_failures do
          expect(params['event']).to eq('destroy')
          expect(json_native?(params)).to be(true), "params is #{params.inspect}"
        end
      end
    end
  end
end
