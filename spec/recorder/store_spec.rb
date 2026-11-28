# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Store do
  let(:manager) { Class.new { include Recorder::Manager }.new }
  let(:request_info) { {user_id: 1, ip: '127.0.0.1'} }

  # Each runs the block somewhere other than the current fiber and returns its
  # value.
  def in_fiber(&block)
    Fiber.new(&block).resume
  end

  def in_enumerator(&block)
    Enumerator.new { |yielder| yielder << block.call }.next
  end

  def in_thread(&block)
    Thread.new(&block).value
  end

  def save_security
    Security.create!(name: 'Facebook', identifier: 'FB')
  end

  context 'when inheritable fiber storage is available (Ruby 3.2+)', if: Fiber.respond_to?(:[]) do
    {'a new fiber' => :in_fiber, 'an Enumerator#next body' => :in_enumerator}.each do |place, runner|
      context "in #{place}" do
        it 'has recording off inside recorder_disabled!' do
          observed = manager.recorder_disabled! { send(runner) { Recorder.recording? } }

          expect(observed).to be(false)
        end

        it 'writes no revision inside recorder_disabled!' do
          expect { manager.recorder_disabled! { send(runner) { save_security } } }
            .not_to change(Recorder::Revision, :count)
        end

        it 'has the request info' do
          Recorder.info = request_info

          expect(send(runner) { Recorder.store.params }).to include(request_info)
        end

        it 'writes the request info on the revision' do
          Recorder.info = request_info

          revision = send(runner) { save_security }.revisions.last

          expect([revision.user_id, revision.ip.to_s]).to eq([1, '127.0.0.1'])
        end
      end
    end

    describe 'the switch' do
      it 'stays off in a fiber started inside recorder_disabled! and resumed after it' do
        fiber = manager.recorder_disabled! { Fiber.new { Recorder.recording? } }

        expect(fiber.resume).to be(false)
      end

      it 'stays as it was in a fiber started before recorder_disabled! and resumed inside it' do
        Recorder.info = request_info
        fiber = Fiber.new { [Recorder.recording?, Recorder.store.params[:user_id]] }

        expect(manager.recorder_disabled! { fiber.resume }).to eq([true, 1])
      end

      it 'is not switched off for the creating fiber by recorder_disabled! in a new one' do
        Recorder.info = request_info
        in_fiber { manager.recorder_disabled! }

        expect(Recorder.recording?).to be(true)
      end

      it 'reaches a fiber started by a fiber started inside recorder_disabled!' do
        observed = manager.recorder_disabled! { in_fiber { in_fiber { Recorder.recording? } } }

        expect(observed).to be(false)
      end
    end

    describe 'the request info' do
      it 'is copied, so Recorder.info= in a new fiber leaves the creating fiber as it was' do
        Recorder.info = request_info
        in_fiber { Recorder.info = {user_id: 2} }

        expect(Recorder.store.params).to include(user_id: 1)
      end

      it 'is copied when a new fiber first uses it, so later changes in the creating fiber do not reach it' do
        Recorder.info = request_info
        fiber =
          Fiber.new do
            Recorder.store.params
            Fiber.yield
            Recorder.store.params[:user_id]
          end
        fiber.resume
        Recorder.info = {user_id: 2}

        expect(fiber.resume).to eq(1)
      end
    end

    describe 'when RequestStore is reset' do
      it 'is not passed on after RequestStore.clear! to a fiber started before the store is used again' do
        Recorder.info = request_info
        manager.recorder_disabled!
        RequestStore.clear!

        expect(in_fiber { [Recorder.recording?, Recorder.store.params] }).to eq([true, {}])
      end

      it 'is not passed on after RequestStore.store= to a fiber started before the store is used again' do
        Recorder.info = request_info
        RequestStore.store = {}

        expect(in_fiber { Recorder.store.params }).to eq({})
      end

      it "is not passed on after RequestStore's middleware ends a request" do
        app =
          lambda do |_env|
            Recorder.info = request_info
            [200, {}, []]
          end
        _status, _headers, body = RequestStore::Middleware.new(app).call({})
        body.close

        expect(in_fiber { Recorder.store.params }).to eq({})
      end

      it 'is not taken up again by the fiber that passed it on, when RequestStore lost it some other way' do
        Recorder.info = request_info
        RequestStore.delete(:recorder)

        expect(Recorder.store.params).to eq({})
      end
    end

    it 'passes a thread state on to the fibers that thread starts' do
      Recorder.info = request_info

      observed =
        in_thread do
          Recorder.info = {user_id: 2}
          in_fiber { Recorder.store.params }
        end

      expect(observed).to eq(user_id: 2)
    end
  end

  context 'when inheritable fiber storage is not available (Ruby 3.0 and 3.1)', unless: Fiber.respond_to?(:[]) do
    {'a new fiber' => :in_fiber, 'an Enumerator#next body' => :in_enumerator}.each do |place, runner|
      context "in #{place}" do
        it 'has recording on inside recorder_disabled!' do
          observed = manager.recorder_disabled! { send(runner) { Recorder.recording? } }

          expect(observed).to be(true)
        end

        it 'does not have the request info' do
          Recorder.info = request_info

          expect(send(runner) { Recorder.store.params }).to eq({})
        end
      end
    end
  end

  context 'in a new thread' do
    it 'has recording on inside recorder_disabled!' do
      observed = manager.recorder_disabled! { in_thread { Recorder.recording? } }

      expect(observed).to be(true)
    end

    it 'writes a revision inside recorder_disabled!' do
      expect { manager.recorder_disabled! { in_thread { save_security } } }
        .to change(Recorder::Revision, :count).by(1)
    end

    it 'does not have the request info' do
      Recorder.info = request_info

      expect(in_thread { Recorder.store.params }).to eq({})
    end

    it 'has recording on in a fiber it starts inside recorder_disabled!' do
      observed = manager.recorder_disabled! { in_thread { in_fiber { Recorder.recording? } } }

      expect(observed).to be(true)
    end

    it 'carries nothing from the request it was started in into later work' do
      jobs = Queue.new
      Recorder.info = request_info
      worker = manager.recorder_disabled! { Thread.new { while (job = jobs.pop) do job.call end } }
      RequestStore.clear!

      later = Queue.new
      jobs << -> { later << [Recorder.recording?, Recorder.store.params] }
      jobs.close
      worker.join

      expect(later.pop).to eq([true, {}])
    end
  end
end
