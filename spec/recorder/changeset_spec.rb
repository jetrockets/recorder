require "rails_helper"

module Recorder
  RSpec.describe Changeset do
    describe "#initialize" do
      let(:item) { Security.new }
      let(:changes) { Hash.new }

      it 'is correctly sets instance variables' do
        changeset = described_class.new(item, changes)

        expect(changeset.instance_variable_get(:@item)).to eql(item)
        expect(changeset.instance_variable_get(:@changes)).to eql(changes)
      end
    end
  end
end
