# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      def record(params)
        return unless Recorder.recording?

        Recorder::Revision.create(params_for(params))
      end

      private

      # A revision is dated by the request that made the change, or else today
      # in the application's time zone.
      def params_for(params)
        Recorder.store.params.merge(params).tap do |merged|
          merged[:action_date] = merged[:action_date].presence || Date.current
        end
      end
    end
  end
end
