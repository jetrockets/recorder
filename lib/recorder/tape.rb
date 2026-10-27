# frozen_string_literal: true

require 'recorder/tape/data'
require 'recorder/tape/record'

module Recorder
  # Writes a record's revisions. Called directly, it skips the model's `if:`
  # and `unless:`, and still honours `Recorder.recording?`.
  class Tape
    extend Record

    attr_reader :item, :data

    def initialize(item)
      @item = item
      @data = Data.new(item)
    end

    def record_create
      record(event: 'create', data: data_for(:create, recorder_options))
    end

    # An update that changed nothing has no data and writes no revision.
    def record_update
      data = data_for(:update, recorder_options)

      record(event: 'update', data: data) if data.any?
    end

    def record_destroy
      record(event: 'destroy', data: data_for(:destroy, recorder_options))
    end

    protected

    def recorder_options
      item.respond_to?(:recorder_options, true) ? item.send(:recorder_options) : {}
    end

    def data_for(event, options)
      data.data_for(event, options)
    end

    def record(params)
      Recorder::Tape.record(
        # The value `has_many :revisions` looks rows up by: the base class
        # of an STI subclass.
        item_type: item.class.polymorphic_name,
        item_id: item.id,
        **params
      )
    end
  end
end
