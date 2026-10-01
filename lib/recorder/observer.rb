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

    # Options passed to `.recorder`. A model may define this itself to decide
    # them per record.
    def recorder_options
      self.class.recorder_options
    end

    class_methods do
      # The options passed to `.recorder` in this class or the nearest ancestor.
      def recorder_options
        return @recorder_options if defined?(@recorder_options)

        superclass.respond_to?(:recorder_options) ? superclass.recorder_options : {}
      end

      # Registers the callbacks, which subclasses inherit, so it is called once
      # per class hierarchy.
      def recorder(options = {})
        declared_in = [*ancestors, *descendants].find { |klass| klass.instance_variable_defined?(:@recorder_options) }
        if declared_in
          raise ArgumentError, "`recorder` is already declared in #{declared_in.name || declared_in.inspect}. " \
            'Declare it once per class hierarchy, in the topmost class that records, and define a ' \
            '`recorder_options` instance method where a subclass needs other options.'
        end

        Recorder::Tape::Data.validate_changes_option!(options[:changes])

        after_create do
          Recorder::Tape.new(self).record_create if recorder_record?
        end

        after_update do
          Recorder::Tape.new(self).record_update if recorder_record?
        end

        after_destroy do
          Recorder::Tape.new(self).record_destroy if recorder_record?
        end

        @recorder_options = options
      end
    end
  end
end
