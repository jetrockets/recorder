# frozen_string_literal: true

# No single class under test here.
# rubocop:disable RSpec/DescribeClass

require 'rails_helper'

# Guards the isolation configured in spec/rails_helper.rb.
#
# Both examples assert a clean slate, then dirty it. Whichever runs second
# catches a leak, so this holds under `config.order = :random`.
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
