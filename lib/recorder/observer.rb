# frozen_string_literal: true

require 'recorder/tape'
require 'recorder/update_columns'
require 'active_support/concern'
require 'active_support/core_ext/object/deep_dup'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    # The condition every `recorder` callback checks before the model's own.
    RECORDING = -> { Recorder.recording? }

    included do
      has_many :revisions, class_name: '::Recorder::Revision', inverse_of: :item, as: :item
    end

    # A copy of the options passed to `.recorder`, which the caller may change.
    # A model may define this itself to decide them per record, all but `if:`
    # and `unless:`, which the callbacks hold.
    def recorder_options
      self.class.recorder_options.deep_dup
    end

    # Writes the attributes like `update_columns`, without validations or
    # callbacks, and records the write as an `update` revision in the same
    # transaction. Without attributes, writes the record's unsaved changes.
    # Returns `true`, or `false` when there was no row to update.
    def recorder_update_columns(attributes = nil)
      Recorder::UpdateColumns.new(self).call(attributes)
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

      # The `if:` and `unless:` passed to `.recorder`, which the callbacks
      # hold, or `nil` until `.recorder` is called in the hierarchy.
      def recorder_conditions
        declared_in = recorder_declared_in
        return unless declared_in

        declared_in.instance_variable_get(:@recorder_options).slice(:if, :unless)
      end

      # Registers the callbacks, which subclasses inherit, so it is called once
      # per class hierarchy. The callbacks hold `if:` and `unless:`, so the
      # `recorder_options` overrides cannot change them.
      def recorder(options = {})
        declared_in = [*ancestors, *descendants].find { |klass| klass.instance_variable_defined?(:@recorder_options) }
        if declared_in
          raise ArgumentError, "`recorder` is already declared in #{declared_in.name || declared_in.inspect}. " \
            'Declare it once per class hierarchy, in the topmost class that records, and define a ' \
            '`recorder_options` instance method where a subclass needs other options. `if:` and `unless:` ' \
            'stay as declared.'
        end

        options = Recorder::Options.normalize(options)
        # Rails checks the conditions in order, so the model's own runs only
        # while recording is on.
        conditions = {if: [RECORDING, options[:if]].compact, unless: options[:unless]}

        after_create(**conditions) do
          Recorder::Tape.new(self).record_create
        end

        after_update(**conditions) do
          Recorder::Tape.new(self).record_update
        end

        after_destroy(**conditions) do
          Recorder::Tape.new(self).record_destroy
        end

        @recorder_options = options
      end
    end
  end
end
