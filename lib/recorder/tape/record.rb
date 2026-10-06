# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      def record(params)
        return unless Recorder.recording?

        Recorder::Revision.create!(params_for(params))
      # Re-raised as an error Active Record's save does not rescue, so the save
      # fails, whichever method it was made with.
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        raise Recorder::RevisionNotSaved.new("Recorder could not write the revision: #{e.message}", e.record)
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
