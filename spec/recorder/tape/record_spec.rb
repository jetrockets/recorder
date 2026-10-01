# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Tape::Record do
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

    it 'writes the revision before the save returns' do
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.pluck(:event)).to eq(['create'])
    end
  end
end
