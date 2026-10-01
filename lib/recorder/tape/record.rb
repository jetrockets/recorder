# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      def record(params)
        return if Recorder.store.recorder_disabled?

        Recorder::Revision.create(params_for(params))
      end

      private

      def params_for(params)
        Recorder.store.params.merge({
          action_date: Date.today,
          **params
        })
      end
    end
  end
end
