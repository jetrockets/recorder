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

    context 'with a Proc' do
      let(:calls) { [] }

      # Returns the number of the call, so each call gives a different value.
      let(:counted) { -> { {call: calls.push(:call).size} } }

      def create_security(identifier = 'FB')
        Security.create!(name: 'Facebook', identifier: identifier)
      end

      it 'does not call it until a revision is written' do
        described_class.meta = counted

        expect(calls).to be_empty
      end

      it 'writes its value on the revision' do
        described_class.meta = counted

        expect(create_security.revisions.last.meta).to eq('call' => 1)
      end

      it 'calls it once for all the revisions that follow' do
        described_class.meta = counted
        security = create_security
        security.update!(name: 'Meta')
        security.destroy!

        expect(calls.size).to eq(1)
        expect(security.revisions.pluck(:meta)).to eq([{'call' => 1}] * 3)
      end

      it 'keeps its value in its place' do
        described_class.meta = counted
        create_security

        expect(described_class.store.params[:meta]).to eq(call: 1)
      end

      it 'writes its value on a revision written through Tape' do
        described_class.meta = counted
        Recorder::Tape.record(item_type: 'Security', item_id: 1, event: 'create', data: {attributes: {name: 'Facebook'}})

        expect(Recorder::Revision.last.meta).to eq('call' => 1)
      end

      it 'is not called while recording is off' do
        described_class.meta = counted
        described_class.store.recorder_disabled!
        create_security

        expect(calls).to be_empty
      end

      it 'is not called by an update that writes no revision' do
        security = create_security
        described_class.meta = counted
        security.update!(name: 'Facebook')

        expect(calls).to be_empty
      end

      it 'is not called once a hash replaces it' do
        described_class.meta = counted
        described_class.meta = {locale: 'en'}

        expect(create_security.revisions.last.meta).to eq('locale' => 'en')
        expect(calls).to be_empty
      end

      it 'gives no meta to a revision written from inside it' do
        described_class.meta =
          lambda do
            create_security('IN')
            {locale: 'en'}
          end
        create_security

        expect(Security.find_by!(identifier: 'IN').revisions.last.meta).to be_nil
        expect(Security.find_by!(identifier: 'FB').revisions.last.meta).to eq('locale' => 'en')
      end

      context 'when it raises' do
        it 'fails the save and rolls it back' do
          described_class.meta = -> { raise KeyError, 'no meta' }

          expect { create_security }.to raise_error(KeyError, 'no meta')
          expect(Security.where(identifier: 'FB')).not_to exist
        end

        it 'is called again by the next revision' do
          described_class.meta =
            lambda do
              calls << :call
              raise KeyError, 'no meta' if calls.one?

              {locale: 'en'}
            end

          expect { create_security }.to raise_error(KeyError)
          expect(create_security.revisions.last.meta).to eq('locale' => 'en')
        end

        # Active Record's save returns false on RecordInvalid, so the error
        # would otherwise leave the record unsaved without raising.
        it 'raises from save when it fails validation' do
          user = User.new.tap { |record| record.errors.add(:name, :blank) }
          described_class.meta = -> { raise ActiveRecord::RecordInvalid, user }

          expect { Security.new(name: 'Facebook', identifier: 'FB').save }
            .to raise_error(Recorder::RevisionNotSaved, /Name can't be blank/)
          expect(Security.where(identifier: 'FB')).not_to exist
        end
      end
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
