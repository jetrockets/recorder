require 'recorder/tape/data'
require 'recorder/tape/record'

module Recorder
  class Tape
    extend Record

    attr_reader :item, :data

    def initialize(item)
      @item = item;
      @data = Data.new(item)

      item.instance_variable_set(:@recorder_dirty, true)
    end

    def record_create
      data = data_for(:create, recorder_options)

      if data.any?
        record(event: :create, data: data)
      end
    end

    def record_update
      data = data_for(:update, recorder_options)

      if data.any?
        record(event: :update, data: data)
      end
    end

    def record_destroy
      data = data_for(:destroy, recorder_options)

      if data.any?
        record(event: :destroy, data: data)
      end
    end

  protected

    def recorder_options
      item.respond_to?(:recorder_options) ? item.recorder_options : {}
    end

    def data_for(event, options)
      data.data_for(event, options)
    end

    def record(params)
      Recorder::Tape.record(
        {
          item_type: item.class.to_s,
          item_id: item.id,
          **params
        },
        item.recorder_options
      )
    end
  end
end
