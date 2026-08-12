# frozen_string_literal: true

# This file guards the suite itself rather than any one class, so there is no
# class to hand to `describe`.
# rubocop:disable RSpec/DescribeClass

require 'rails_helper'

# Guards the isolation set up in spec/rails_helper.rb. Remove any part of that
# `config.before` block, or the transactional fixtures, and this file fails.
#
# Both examples do the same thing: assert the world is clean, then dirty every
# piece of it. Whichever one RSpec happens to run second is the one that catches
# a leak, so this holds under `config.order = :random` without pinning an order.
RSpec.describe 'spec suite isolation' do
  %w[first second].each do |pass|
    it "starts from a clean slate (#{pass} pass)" do
      aggregate_failures do
        expect(Security.count).to eq(0)
        expect(Recorder::Revision.count).to eq(0)
        expect(Recorder.config.ignore).to eq([])
        expect(Recorder.store.recorder_enabled?).to be(true)
      end

      Security.create!(name: 'Facebook', identifier: 'FB')
      Recorder.config.ignore = %i[created_at]
      Recorder.store.recorder_disabled!
    end
  end
end

# rubocop:enable RSpec/DescribeClass
