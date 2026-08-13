# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security do
  let(:user) { User.create!(name: 'Igor') }

  before { Recorder.info = {user_id: user.id} }

  describe 'on create' do
    it 'records a revision carrying the attributes' do
      security = described_class.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.count).to eq(1)

      revision = security.revisions.last
      aggregate_failures do
        expect(revision.event).to eq('create')
        expect(revision.item).to eq(security)
        expect(revision.user).to eq(user)
        expect(revision.data['attributes']).to include('name' => 'Facebook', 'identifier' => 'FB')
      end
    end
  end

  describe 'on update' do
    let!(:security) { described_class.create!(name: 'Facebook', identifier: 'FB') }

    it 'records a revision carrying the changes' do
      security.update!(name: 'Meta')

      revision = security.revisions.order(:id).last
      aggregate_failures do
        expect(revision.event).to eq('update')
        # updated_at is in the changeset too: config.ignore is empty by default.
        expect(revision.data['changes']).to include('name' => %w[Facebook Meta])
      end
    end

    it 'records nothing when nothing changed' do
      expect { security.update!(name: 'Facebook') }.not_to change(Recorder::Revision, :count)
    end
  end

  describe 'on destroy' do
    let!(:security) { described_class.create!(name: 'Facebook', identifier: 'FB') }

    it 'records a revision' do
      expect { security.destroy! }.to change(Recorder::Revision, :count).by(1)

      expect(Recorder::Revision.order(:id).last.event).to eq('destroy')
    end
  end

  describe 'when recording is disabled' do
    it 'records nothing' do
      Recorder.store.recorder_disabled!

      expect { described_class.create!(name: 'Facebook', identifier: 'FB') }
        .not_to change(Recorder::Revision, :count)
    end
  end
end
