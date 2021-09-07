# frozen_string_literal: true

require 'recorder/tape'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, class_name: '::Recorder::Revision', inverse_of: :item, as: :item
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
          Recorder::Tape.new(self).record_create if recorder_record?
        end

        after_update do
          Recorder::Tape.new(self).record_update if recorder_record?
        end

        after_destroy do
          Recorder::Tape.new(self).record_destroy if recorder_record?
        end
      end
    end
  end
end
