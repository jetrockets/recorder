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

  describe '.config' do
    it 'returns the configuration' do
      expect(described_class.config).to equal(Recorder::Config.instance)
    end

    it 'yields the configuration to a block' do
      described_class.config { |config| config.enabled = false }

      expect(described_class.enabled?).to be(false)
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

  describe '.meta=' do
    it 'keeps the meta for the revisions that follow' do
      described_class.meta = {locale: 'en'}

      expect(described_class.store.params[:meta]).to eq(locale: 'en')
    end

    it 'is written on the revisions that follow' do
      described_class.meta = {locale: 'en'}
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to eq('locale' => 'en')
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

  describe '.with_info' do
    let(:params) { described_class.store.params }
    let(:manager) { Class.new { include Recorder::Manager }.new }

    def write_revision
      Security.create!(name: 'Facebook', identifier: 'FB').revisions.last
    end

    describe 'scope' do
      it 'applies the info to the revisions written inside the block' do
        revision = described_class.with_info(user_id: 7, meta: {reason: 'Scheduled'}) { write_revision }

        expect(revision).to have_attributes(user_id: 7, meta: {'reason' => 'Scheduled'})
      end

      it 'applies the info to the revisions Recorder::Tape writes' do
        described_class.with_info(user_id: 7) do
          Recorder::Tape.record(item_type: 'Security', item_id: 1, event: 'create', data: {attributes: {name: 'FB'}})
        end

        expect(Recorder::Revision.last.user_id).to eq(7)
      end

      it 'leaves the revisions written after the block without it' do
        described_class.with_info(user_id: 7, meta: {reason: 'Scheduled'}) { nil }

        expect(write_revision).to have_attributes(user_id: nil, meta: nil)
      end

      it "returns the block's value" do
        expect(described_class.with_info(user_id: 7) { :value }).to eq(:value)
      end

      it 'applies to the current thread only' do
        described_class.info = {user_id: 1}
        inside = Queue.new
        release = Queue.new
        thread =
          Thread.new do
            described_class.with_info(user_id: 2) do
              inside << described_class.user_id
              release.pop
            end
          rescue => e
            inside << e
          end

        expect(inside.pop).to eq(2)
        expect(described_class.user_id).to eq(1)
      ensure
        release << true
        thread.join
      end

      # Recorder.store is fiber-local; see Known issues in the README.
      it 'reaches neither a fiber nor a thread started inside the block' do
        described_class.info = {user_id: 1}

        seen =
          described_class.with_info(user_id: 7) do
            [Fiber.new { described_class.user_id }.resume, Thread.new { described_class.user_id }.value]
          end

        expect(seen).to eq([nil, nil])
      end
    end

    describe 'restoring the info' do
      it 'removes a key that was absent' do
        described_class.with_info(user_id: 7) { nil }

        expect(params).not_to have_key(:user_id)
      end

      it 'restores the earlier value of a key' do
        described_class.info = {user_id: 1}
        described_class.with_info(user_id: 7) { nil }

        expect(params).to eq(user_id: 1)
      end

      it 'restores a key that was explicitly nil' do
        described_class.info = {user_id: nil}
        described_class.with_info(user_id: 7) { nil }

        expect(params).to eq(user_id: nil)
      end

      it 'removes the meta when there was none' do
        described_class.with_info(meta: {reason: 'Scheduled'}) { nil }

        expect(params).not_to have_key(:meta)
      end

      it 'restores a nil meta' do
        described_class.meta = nil
        described_class.with_info(meta: {reason: 'Scheduled'}) { nil }

        expect(params).to eq(meta: nil)
      end

      it 'restores the earlier meta Hash itself, unchanged' do
        meta = {locale: 'en'}
        described_class.meta = meta
        described_class.with_info(meta: {reason: 'Scheduled'}) { nil }

        expect(params[:meta]).to equal(meta).and eq(locale: 'en')
      end

      it 'gives a block that sets no meta a copy of the meta, so writes into it end with the block' do
        meta = {locale: 'en'}
        described_class.meta = meta

        described_class.with_info(user_id: 7) { params[:meta][:reason] = 'Scheduled' }

        expect(params[:meta]).to equal(meta).and eq(locale: 'en')
      end

      it 'restores a meta key the block also set' do
        described_class.meta = {reason: 'Manual', locale: 'en'}
        described_class.with_info(meta: {reason: 'Scheduled'}) { nil }

        expect(params[:meta]).to eq(reason: 'Manual', locale: 'en')
      end

      it 'restores the info when the block raises, and re-raises the error' do
        described_class.info = {user_id: 1, meta: {locale: 'en'}}

        expect { described_class.with_info(user_id: 7, meta: {reason: 'Scheduled'}) { raise 'boom' } }
          .to raise_error(RuntimeError, 'boom')
        expect(params).to eq(user_id: 1, meta: {locale: 'en'})
      end

      it 'applies info= written inside the block to the rest of the block' do
        revision =
          described_class.with_info(user_id: 7) do
            described_class.info = {ip: '10.0.0.1'}
            write_revision
          end

        expect(revision).to have_attributes(user_id: 7, ip: IPAddr.new('10.0.0.1'))
      end

      it 'undoes info= written inside the block' do
        described_class.info = {ip: '127.0.0.1'}
        described_class.with_info(user_id: 7) { described_class.info = {ip: '10.0.0.1', action_date: Date.new(2020, 1, 1)} }

        expect(params).to eq(ip: '127.0.0.1')
      end

      it 'undoes meta= written inside the block' do
        described_class.meta = {locale: 'en'}
        described_class.with_info(user_id: 7) { described_class.meta = {locale: 'fr'} }

        expect(params).to eq(meta: {locale: 'en'})
      end
    end

    describe 'nesting' do
      it 'stacks an inner block on an outer one' do
        described_class.meta = {locale: 'en'}

        revision =
          described_class.with_info(user_id: 7, meta: {reason: 'Scheduled'}) do
            described_class.with_info(meta: {reason: 'Retry', attempt: 2}) { write_revision }
          end

        expect(revision).to have_attributes(user_id: 7, meta: {'locale' => 'en', 'reason' => 'Retry', 'attempt' => 2})
      end

      it 'unwinds to the outer block, then to the info before both' do
        described_class.meta = {locale: 'en'}
        after_inner = nil

        described_class.with_info(user_id: 7, meta: {reason: 'Scheduled'}) do
          described_class.with_info(user_id: 8, meta: {reason: 'Retry'}) { nil }
          after_inner = params.dup
        end

        expect(after_inner).to eq(user_id: 7, meta: {locale: 'en', reason: 'Scheduled'})
        expect(params).to eq(meta: {locale: 'en'})
      end

      it 'unwinds an inner block that raises to the outer block' do
        after_inner = nil

        described_class.with_info(user_id: 7) do
          described_class.with_info(user_id: 8) { raise 'boom' }
        rescue RuntimeError
          after_inner = params.dup
        end

        expect(after_inner).to eq(user_id: 7)
        expect(params).to be_empty
      end
    end

    describe 'the keys it sets' do
      it 'merges meta into the current meta' do
        described_class.meta = {locale: 'en'}

        meta = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta }

        expect(meta).to eq(locale: 'en', reason: 'Scheduled')
      end

      it 'replaces a meta key the current meta has' do
        described_class.meta = {reason: 'Manual'}

        meta = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta }

        expect(meta).to eq(reason: 'Scheduled')
      end

      it 'uses its meta when there is no current meta' do
        meta = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta }

        expect(meta).to eq(reason: 'Scheduled')
      end

      it 'clears the meta for the block when given nil' do
        described_class.meta = {locale: 'en'}

        revision = described_class.with_info(meta: nil) { write_revision }

        expect(revision.meta).to be_nil
        expect(params).to eq(meta: {locale: 'en'})
      end

      it 'replaces the value of any other key' do
        described_class.info = {user_id: 1, ip: '127.0.0.1'}

        revision = described_class.with_info(user_id: 7) { write_revision }

        expect(revision).to have_attributes(user_id: 7, ip: IPAddr.new('127.0.0.1'))
      end

      it 'replaces another key with an explicit nil' do
        described_class.info = {user_id: 1}

        revision = described_class.with_info(user_id: nil) { write_revision }

        expect(revision.user_id).to be_nil
      end

      it 'stores string keys as symbols' do
        described_class.info = {user_id: 1}

        info = described_class.with_info('user_id' => 7, 'meta' => {'reason' => 'Scheduled'}) { params.dup }

        expect(info).to eq(user_id: 7, meta: {reason: 'Scheduled'})
      end

      it 'replaces a key the current meta has as a string' do
        described_class.meta = {'reason' => 'Manual', 'locale' => 'en'}

        revision =
          described_class.with_info(meta: {reason: 'Scheduled'}) do
            expect(described_class.meta).to eq('locale' => 'en', :reason => 'Scheduled')
            write_revision
          end

        expect(revision.meta).to eq('reason' => 'Scheduled', 'locale' => 'en')
      end

      it 'replaces a key the current meta has as both a string and a symbol' do
        described_class.meta = {'reason' => 'Manual', :reason => 'Retry', :locale => 'en'}

        meta = described_class.with_info(meta: {'reason' => 'Scheduled'}) { described_class.meta }

        expect(meta).to eq(locale: 'en', reason: 'Scheduled')
      end

      it 'keeps the keys of the current meta as they are' do
        described_class.meta = {'source' => 'api'}

        source = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta['source'] }

        expect(source).to eq('api')
      end

      it 'keeps a current HashWithIndifferentAccess meta one' do
        described_class.meta = ActiveSupport::HashWithIndifferentAccess.new(source: 'api')

        meta = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta }

        expect(meta).to be_a(ActiveSupport::HashWithIndifferentAccess)
        expect(meta.to_h).to eq('source' => 'api', 'reason' => 'Scheduled')
      end

      it 'leaves no meta as none when given an empty meta' do
        observed = described_class.with_info(meta: {}) { [params.key?(:meta), write_revision.meta] }

        expect(observed).to eq([false, nil])
      end

      it 'leaves the current meta as it is when given an empty meta' do
        described_class.meta = {'source' => 'api'}

        meta = described_class.with_info(meta: {}) { described_class.meta }

        expect(meta).to eq('source' => 'api')
      end

      it 'leaves a current meta that is not a Hash as it is when given an empty meta' do
        described_class.meta = 'Scheduled'

        meta = described_class.with_info(meta: {}) { described_class.meta }

        expect(meta).to eq('Scheduled')
      end

      [{'reason' => 'Manual', :reason => 'Scheduled'}, {:reason => 'Scheduled', 'reason' => 'Manual'}].each do |meta|
        it "keeps the value a revision gets without the block for a meta of #{meta.inspect}" do
          described_class.meta = meta

          without = write_revision.meta['reason']
          within = described_class.with_info(meta: {locale: 'en'}) { write_revision.meta['reason'] }

          expect(within).to eq(without)
        end
      end
    end

    describe 'what it refuses' do
      %i[id item_type item_id event data created_at].each do |column|
        it "refuses #{column}, which Recorder writes itself, before running the block" do
          ran = false

          expect { described_class.with_info(column => 'anything') { ran = true } }
            .to raise_error(ArgumentError, /Recorder.with_info cannot set columns Recorder writes itself: #{column}\./)
          expect(ran).to be(false)
        end
      end

      it 'refuses a reserved column given as a string key' do
        expect { described_class.with_info('created_at' => Time.current) { nil } }.to raise_error(ArgumentError, /created_at/)
      end

      it 'refuses meta that is neither a Hash nor nil' do
        expect { described_class.with_info(meta: [:reason]) { nil } }
          .to raise_error(ArgumentError, /takes a Hash as meta:, or nil for none, not Array/)
      end

      it 'refuses to merge into a current meta that is not a Hash' do
        described_class.meta = 'Scheduled'

        expect { described_class.with_info(meta: {reason: 'Retry'}) { nil } }
          .to raise_error(ArgumentError, /cannot merge meta: into the current meta, a String/)
      end

      it 'refuses to run without a block' do
        expect { described_class.with_info(user_id: 7) }.to raise_error(ArgumentError, /needs a block/)
      end

      it 'changes none of the info when it refuses' do
        described_class.info = {user_id: 1}

        expect { described_class.with_info(user_id: 7, data: {}) { nil } }.to raise_error(ArgumentError)
        expect { described_class.with_info(user_id: 7, meta: 'Retry') { nil } }.to raise_error(ArgumentError)
        expect { described_class.with_info(user_id: 7) }.to raise_error(ArgumentError)
        expect(params).to eq(user_id: 1)
      end
    end

    describe 'the Hashes it is given' do
      it "leaves the caller's Hash and its meta unchanged" do
        info = {'user_id' => 7, :meta => {'reason' => 'Scheduled'}}
        described_class.meta = {locale: 'en'}

        described_class.with_info(info) { nil }

        expect(info).to eq('user_id' => 7, :meta => {'reason' => 'Scheduled'})
        expect(info).not_to be_frozen
      end

      it "stores a copy of the caller's meta" do
        meta = {reason: 'Scheduled'}

        described_class.with_info(meta: meta) { params[:meta][:attempt] = 2 }

        expect(meta).to eq(reason: 'Scheduled')
      end

      it "leaves the outer block's meta Hash unchanged" do
        outer = nil

        described_class.with_info(meta: {reason: 'Scheduled'}) do
          outer = params[:meta]
          described_class.with_info(meta: {attempt: 2}) { nil }
        end

        expect(outer).to eq(reason: 'Scheduled')
      end
    end

    describe 'with recorder_disabled!' do
      it 'leaves recording off after recorder_disabled! called inside the block' do
        described_class.with_info(user_id: 7) { manager.recorder_disabled! }

        expect(described_class.recording?).to be(false)
      end

      it 'leaves the info in place for the rest of the block after a recorder_disabled! block' do
        described_class.with_info(user_id: 7) do
          manager.recorder_disabled! { write_revision }
          write_revision
        end

        expect(Recorder::Revision.pluck(:user_id)).to eq([7])
      end

      it 'writes nothing inside a recorder_disabled! block and restores both afterwards' do
        expect do
          manager.recorder_disabled! do
            described_class.with_info(user_id: 7) { Security.create!(name: 'Facebook', identifier: 'FB') }
          end
        end.not_to change(Recorder::Revision, :count)

        expect(params).to be_empty
        expect(described_class.recording?).to be(true)
      end
    end
  end

  describe '.info' do
    it 'returns the current info' do
      described_class.info = {user_id: 1, ip: '127.0.0.1', meta: {locale: 'en'}}

      expect(described_class.info).to eq(user_id: 1, ip: '127.0.0.1', meta: {locale: 'en'})
    end

    it 'returns an empty Hash when no info is set' do
      expect(described_class.info).to eq({})
    end

    it 'reflects a with_info block inside it and not after it' do
      inside = described_class.with_info(user_id: 7) { described_class.info }

      expect(inside).to eq(user_id: 7)
      expect(described_class.info).to eq({})
    end

    it 'returns a frozen copy, nested values included' do
      described_class.info = {ip: +'127.0.0.1', meta: {tags: [+'import'], source: {name: +'csv'}}}

      info = described_class.info

      expect([info,
        info[:ip],
        info[:meta],
        info[:meta][:tags],
        info[:meta][:tags].first,
        info[:meta][:source],
        info[:meta][:source][:name]]).to all(be_frozen)
      expect(info[:ip]).not_to equal(described_class.store.params[:ip])
      expect(described_class.store.params[:meta][:tags]).not_to be_frozen
    end

    it 'can be merged and written back' do
      described_class.info = {user_id: 1, ip: +'127.0.0.1', meta: {source: {name: +'csv'}}}

      described_class.info = described_class.info.merge(user_id: 2)

      expect(Security.create!(name: 'Facebook', identifier: 'FB').revisions.last)
        .to have_attributes(user_id: 2, ip: IPAddr.new('127.0.0.1'), meta: {'source' => {'name' => 'csv'}})
    end

    context 'with an Active Record object in the info' do
      let!(:user) { User.create!(name: 'Ann') }

      it 'returns the object itself, without initializing a copy' do
        initialized = 0
        User.define_method(:spec_initialized) { initialized += 1 }
        User.set_callback(:initialize, :after, :spec_initialized)
        described_class.info = {user: user}

        expect(described_class.info[:user]).to equal(user)
        expect(initialized).to eq(0)
      ensure
        User.skip_callback(:initialize, :after, :spec_initialized)
        User.remove_method(:spec_initialized)
      end

      it 'writes the user on the revisions that follow once merged and written back' do
        described_class.info = {user: user}

        described_class.info = described_class.info.merge(meta: {reason: 'Scheduled'})

        expect(Security.create!(name: 'Facebook', identifier: 'FB').revisions.last.user_id).to eq(user.id)
      end
    end
  end

  describe '.meta' do
    it 'returns the current meta' do
      described_class.meta = {locale: 'en'}

      expect(described_class.meta).to eq(locale: 'en')
    end

    it 'is nil when no meta is set' do
      expect(described_class.meta).to be_nil
    end

    it 'reflects a with_info block inside it and not after it' do
      described_class.meta = {locale: 'en'}

      inside = described_class.with_info(meta: {reason: 'Scheduled'}) { described_class.meta }

      expect(inside).to eq(locale: 'en', reason: 'Scheduled')
      expect(described_class.meta).to eq(locale: 'en')
    end

    it 'returns a frozen copy, nested values included' do
      described_class.meta = {source: {name: +'csv'}}

      meta = described_class.meta

      expect([meta, meta[:source], meta[:source][:name]]).to all(be_frozen)
      expect { meta[:source][:name] << 'x' }.to raise_error(FrozenError)
      expect(described_class.store.params[:meta]).to eq(source: {name: 'csv'})
    end

    it 'can be merged and written back' do
      described_class.meta = {source: {name: +'csv'}}

      described_class.meta = described_class.meta.merge(reason: 'Scheduled')

      expect(Security.create!(name: 'Facebook', identifier: 'FB').revisions.last.meta)
        .to eq('source' => {'name' => 'csv'}, 'reason' => 'Scheduled')
    end

    it 'returns a class in the meta as it is, without freezing it' do
      job = stub_const('ReportJob', Class.new)
      described_class.meta = {source: job}

      expect(described_class.meta[:source]).to equal(job)
      expect(job).not_to be_frozen
    end

    it 'returns a HashWithIndifferentAccess as a frozen one' do
      described_class.meta = ActiveSupport::HashWithIndifferentAccess.new(source: {name: +'csv'})

      meta = described_class.meta

      expect(meta).to be_a(ActiveSupport::HashWithIndifferentAccess)
      expect([meta, meta[:source], meta['source']['name']]).to all(be_frozen)
    end
  end

  describe '.user_id' do
    it 'returns the current user id' do
      described_class.info = {user_id: 1}

      expect(described_class.user_id).to eq(1)
    end

    it 'is nil when no user id is set' do
      expect(described_class.user_id).to be_nil
    end

    it 'reflects a with_info block inside it and not after it' do
      described_class.info = {user_id: 1}

      expect(described_class.with_info(user_id: 7) { described_class.user_id }).to eq(7)
      expect(described_class.user_id).to eq(1)
    end

    it 'returns a frozen copy of a String id' do
      id = +'9f8e7d6c-0000-4000-8000-000000000000'
      described_class.info = {user_id: id}

      expect(described_class.user_id).to be_frozen.and eq(id)
      expect(id).not_to be_frozen
    end
  end
end
