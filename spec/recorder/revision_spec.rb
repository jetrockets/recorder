# frozen_string_literal: true

require 'rails_helper'

module Recorder
  RSpec.describe Revision do
    let(:user) { User.create!(name: 'Igor') }

    # `Tape::Record#record` calls `create`, not `create!`, so a revision that
    # fails validation is dropped without raising.
    #
    # That matters more than it looks. `belongs_to :user` is declared without
    # `optional: true`, and works only because the gem is required before the
    # Active Record railtie applies `belongs_to_required_by_default` — so the
    # reflection is built while the default is still off. It is correct by
    # accident of load order, not by declaration.
    #
    # If that ordering ever shifted, the association would become required,
    # every `create` would fail validation and return an object, and auditing
    # would stop for every model in the app with nothing raised anywhere. These
    # examples fail loudly instead.
    describe 'recording without a user' do
      context 'when no user is set' do
        it 'records a revision' do
          expect { Security.create!(name: 'Facebook', identifier: 'FB') }
            .to change(described_class, :count).by(1)
        end

        it 'leaves the user blank' do
          Security.create!(name: 'Facebook', identifier: 'FB')

          expect(described_class.order(:id).last.user_id).to be_nil
        end
      end

      context 'when the user no longer exists' do
        before { Recorder.info = {user_id: 999_999} }

        it 'records a revision' do
          expect { Security.create!(name: 'Facebook', identifier: 'FB') }
            .to change(described_class, :count).by(1)
        end
      end

      it 'does not require the `user` association' do
        expect(described_class.reflect_on_association(:user).options[:required]).to be_falsey
      end

      it 'considers a revision without a user valid' do
        revision = described_class.new(
          item_type: 'Security', item_id: 1, event: 'create',
          action_date: Date.today, data: {attributes: {}}
        )

        expect(revision).to be_valid
      end
    end

    # The changeset is rebuilt from values that have been through the `jsonb`
    # column, so every attribute comes back out as a string and is cast again.
    describe '#item_changeset' do
      subject(:changeset) { revision.item_changeset }

      let(:security) do
        Security.create!(name: 'Facebook', identifier: 'FB', pricing_factor: BigDecimal('1.5'))
      end
      let(:revision) do
        security.update!(name: 'Meta', pricing_factor: BigDecimal('2.25'))
        described_class.order(:id).last
      end

      before { Recorder.info = {user_id: user.id} }

      it 'returns the values a string attribute held before and after the change' do
        aggregate_failures do
          expect(changeset.previous(:name)).to eq('Facebook')
          expect(changeset.next(:name)).to eq('Meta')
        end
      end

      it 'returns a decimal attribute as a BigDecimal' do
        aggregate_failures do
          expect(changeset.previous(:pricing_factor)).to eq(BigDecimal('1.5'))
          expect(changeset.next(:pricing_factor)).to eq(BigDecimal('2.25'))
        end
      end

      it 'returns the value a datetime attribute held before the change' do
        before_update = security.updated_at

        expect(changeset.previous(:updated_at)).to be_within(0.001).of(before_update)
      end

      it 'returns a datetime attribute in the application time zone' do
        expect(changeset.previous(:updated_at)).to be_a(ActiveSupport::TimeWithZone)
      end
    end
  end
end
