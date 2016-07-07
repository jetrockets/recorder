require 'recorder/tape'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, :class_name => '::Recorder::Revision', :inverse_of => :item, :as => :item
    end

    module ClassMethods
      def recorder(options = {})
        define_method 'recorder_option' do
          options
        end

        after_commit :on => :create do
          Recorder::Tape.new(self).record_create
        end

        after_commit :on => :update do
          Recorder::Tape.new(self).record_update
        end

        after_commit :on => :destroy do
          Recorder::Tape.new(self).record_destroy
        end
      end
    end
  end
end
