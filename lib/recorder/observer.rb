# frozen_string_literal: true

require 'recorder/tape'
require 'active_support/concern'
require 'active_support/core_ext/object/deep_dup'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, class_name: '::Recorder::Revision', inverse_of: :item, as: :item
    end

    # A copy of the options passed to `.recorder`, which the caller may change.
    # A model may define this itself to decide them per record.
    def recorder_options
      self.class.recorder_options.deep_dup
    end

    class_methods do
      # The options passed to `.recorder` in this class or the nearest ancestor,
      # frozen and with symbol keys.
      def recorder_options
        return @recorder_options if defined?(@recorder_options)

        superclass.respond_to?(:recorder_options) ? superclass.recorder_options : Recorder::Options::NONE
      end

      # The class, this one or the nearest ancestor, that called `.recorder`.
      def recorder_declared_in
        return self if instance_variable_defined?(:@recorder_options)

        superclass.recorder_declared_in if superclass.respond_to?(:recorder_declared_in)
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

        options = Recorder::Options.normalize(options)

        after_create do
          Recorder::Tape.new(self).record_create if Recorder.recording?
        end

        after_update do
          Recorder::Tape.new(self).record_update if Recorder.recording?
        end

        after_destroy do
          Recorder::Tape.new(self).record_destroy if Recorder.recording?
        end

        @recorder_options = options
      end
    end
  end
end
