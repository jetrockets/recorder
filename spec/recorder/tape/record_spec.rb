# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape::Record do
  describe 'the action date' do
    include ActiveSupport::Testing::TimeHelpers

    def recorded_action_date
      Security.create!(name: 'Facebook', identifier: 'FB')
      Recorder::Revision.last.action_date
    end

    it 'is the date the request supplied' do
      Recorder.info = {action_date: Date.new(2020, 1, 1)}

      expect(recorded_action_date).to eq(Date.new(2020, 1, 1))
    end

    it 'is the date the request supplied under a string key' do
      Recorder.info = {'action_date' => Date.new(2020, 1, 1)}

      expect(recorded_action_date).to eq(Date.new(2020, 1, 1))
    end

    # At 10:00 UTC only UTC+14 has reached the next day, so the application's
    # date differs from the server's wherever the suite runs.
    it "defaults to today in the application's time zone" do
      Time.use_zone('Pacific/Kiritimati') do
        travel_to(Time.utc(2026, 10, 2, 10)) do
          expect(recorded_action_date).to eq(Date.new(2026, 10, 3))
        end
      end
    end

    [nil, ''].each do |blank|
      it "defaults to today when the request supplied #{blank.inspect}" do
        Recorder.info = {action_date: blank}

        expect(recorded_action_date).to eq(Date.current)
      end
    end
  end

  describe 'the recording check' do
    def record
      Recorder::Tape.record(item_type: 'Security', item_id: 1, event: 'create', data: {attributes: {name: 'Facebook'}})
    end

    it 'writes the revision while recording is on' do
      expect { record }.to change(Recorder::Revision, :count).by(1)
    end

    it 'writes nothing while the process has recording off' do
      Recorder.enabled = false

      expect { record }.not_to change(Recorder::Revision, :count)
    end

    it 'writes nothing while the request has recording off' do
      Recorder.store.recorder_disabled!

      expect { record }.not_to change(Recorder::Revision, :count)
    end
  end

  # Examples already run inside a transaction, so a rollback needs a savepoint
  # of its own.
  def roll_back
    ActiveRecord::Base.transaction(requires_new: true) do
      yield
      raise ActiveRecord::Rollback
    end
  end

  describe 'writing in the save transaction' do
    it 'leaves no revision for a create that rolls back' do
      expect { roll_back { Security.create!(name: 'Facebook', identifier: 'FB') } }
        .not_to change(Recorder::Revision, :count)
    end

    it 'leaves no revision for an update that rolls back' do
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect { roll_back { security.update!(name: 'Meta') } }
        .not_to change(Recorder::Revision, :count)
    end

    it 'leaves no revision for a destroy that rolls back' do
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect { roll_back { security.destroy! } }
        .not_to change(Recorder::Revision, :count)
    end

    it 'writes the revision before the transaction commits' do
      roll_back do
        security = Security.create!(name: 'Facebook', identifier: 'FB')

        expect(security.revisions.pluck(:event)).to eq(['create'])
      end
    end

    it 'rolls the save back when the revision cannot be written' do
      allow(Recorder::Revision).to receive(:create).and_raise(ActiveRecord::StatementInvalid)

      expect { Security.create!(name: 'Facebook', identifier: 'FB') }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect(Security.where(identifier: 'FB')).not_to exist
    end
  end
end
