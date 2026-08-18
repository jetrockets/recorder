# frozen_string_literal: true

require 'recorder/tape/data'
require 'recorder/tape/record'

module Recorder
  class Tape
    extend Record

    attr_reader :item, :data

    def initialize(item)
      @item = item
      @data = Data.new(item)

      item.instance_variable_set(:@recorder_dirty, true)
    end

    def record_create
      data = data_for(:create, recorder_options)

      record(event: 'create', data: data) if data.any?
    end

    def record_update
      data = data_for(:update, recorder_options)

      record(event: 'update', data: data) if data.any?
    end

    def record_destroy
      data = data_for(:destroy, recorder_options)

      record(event: 'destroy', data: data) if data.any?
    end

    protected

    # Instance first: an app may define `recorder_options` as an instance method
    # to work around this having been broken, and that override must keep
    # winning. The class branch covers items that do not include `Observer`.
    def recorder_options
      return item.recorder_options if item.respond_to?(:recorder_options)
      return item.class.recorder_options if item.class.respond_to?(:recorder_options)

      {}
    end

    def data_for(event, options)
      data.data_for(event, options)
    end

    def record(params)
      Recorder::Tape.record(
        {
          # `polymorphic_name`, not `to_s`: the `has_many :revisions` that
          # `Observer` installs is polymorphic, so Active Record looks rows up
          # by the base class name. Writing `to_s` made every revision an STI
          # subclass wrote unreachable from `item.revisions`. Identical to
          # `to_s` for a non-STI model, which is why it never showed.
          item_type: item.class.polymorphic_name,
          item_id: item.id,
          **params
        },
        recorder_options
      )
    end
  end
end
