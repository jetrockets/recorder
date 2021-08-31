require 'recorder/tape'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, :class_name => '::Recorder::Revision', :inverse_of => :item, :as => :item
    end

    def recorder_dirty?
      return @recorder_dirty if defined?(@recorder_dirty)
      true
    end

    def recorder_record?
      recorder_dirty? && Recorder.store.recorder_enabled?
    end

    module ClassMethods
      def recorder(options = {})
        define_method 'recorder_options' do
          options
        end

        after_create do
          if recorder_record?
            Recorder::Tape.new(self).record_create
          end
        end

        after_update do
          if recorder_record?
            Recorder::Tape.new(self).record_update
          end
        end

        after_destroy do
          if recorder_record?
            Recorder::Tape.new(self).record_destroy
          end
        end
      end
    end
  end
end
