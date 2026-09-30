# frozen_string_literal: true

require 'recorder/tape'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, class_name: '::Recorder::Revision', inverse_of: :item, as: :item

      class_attribute :recorder_options, instance_accessor: false, instance_predicate: false, default: {}.freeze
      private_class_method :recorder_options=
    end

    # Registered by `.recorder`, and inherited by subclasses along with the options.
    module Callbacks
      extend ::ActiveSupport::Concern

      included do
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

    def recorder_dirty?
      return @recorder_dirty if defined?(@recorder_dirty)

      true
    end

    def recorder_record?
      recorder_dirty? && Recorder.store.recorder_enabled?
    end

    # Options passed to `.recorder`. A model may define this itself to decide
    # them per record.
    def recorder_options
      self.class.recorder_options
    end

    class_methods do
      def recorder(options = {})
        if self < Callbacks
          declared_by = ancestors.reverse.find { |ancestor| ancestor.is_a?(Class) && ancestor < Callbacks }
          raise ArgumentError, "`recorder` is already declared in #{declared_by} and can be declared once " \
            "per class hierarchy. To change the options for #{self}, define a `recorder_options` instance method."
        end

        Recorder::Tape::Data.validate_changes_option!(options[:changes])

        self.recorder_options = options
        include Callbacks
      end
    end
  end
end
