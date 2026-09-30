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
      # Stores the options, which subclasses inherit, and registers the callbacks
      # once for the whole class hierarchy.
      def recorder(options = {})
        declared_in = [*ancestors, *descendants].find { |klass| klass.instance_variable_defined?(:@recorder_declared) }
        if declared_in
          raise ArgumentError, "`recorder` is already declared in #{declared_in} and can be declared once per " \
            'class hierarchy. Where a class needs other options, define a `recorder_options` instance method.'
        end

        Recorder::Tape::Data.validate_changes_option!(options[:changes])

        @recorder_declared = true
        self.recorder_options = recorder_deep_freeze(options)

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

      private

      # A frozen copy: the options are shared by every subclass.
      def recorder_deep_freeze(value)
        case value
        when Hash then value.to_h { |key, item| [key, recorder_deep_freeze(item)] }.freeze
        when Array then value.map { |item| recorder_deep_freeze(item) }.freeze
        else value
        end
      end
    end
  end
end
