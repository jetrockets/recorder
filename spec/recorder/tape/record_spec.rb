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

    # A throwaway model: `.recorder` registers callbacks, which outlive an example.
    def build_model(options)
      model = stub_const('AsyncInstrument', Class.new(ApplicationRecord) { self.table_name = 'securities' })
      model.include(Recorder::Observer)
      model.recorder(options)
      model
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

    context 'when the model declares its own options' do
      it 'enqueues with the delay the model declares' do
        build_model(delay: 10.seconds).create!(name: 'Facebook', identifier: 'FB')

        expect(enqueued.last.first.to_f).to eq(10.0)
      end

      it 'writes inline when the model declares async: false' do
        model = build_model(async: false)

        expect { model.create!(name: 'Facebook', identifier: 'FB') }
          .to change(Recorder::Revision, :count).by(1)

        expect(enqueued).to be_empty
      end
    end

    context 'when only the model asks for async' do
      before { Recorder.config.async = false }

      it 'enqueues instead of writing a revision row' do
        model = build_model(async: true)

        expect { model.create!(name: 'Facebook', identifier: 'FB') }
          .not_to change(Recorder::Revision, :count)

        expect(enqueued.size).to eq(1)
      end
    end

    it 'enqueues an STI subclass under its base class, as an inline write stores it' do
      Bond.create!(name: 'Treasury', identifier: 'UST')

      expect(enqueued.last.last['item_type']).to eq('Instrument')
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
