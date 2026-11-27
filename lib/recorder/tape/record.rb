# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      def record(params)
        return unless Recorder.recording?

        revision = Recorder::Revision.new(params_for(params))
        revision.save!
      # The failure of a revision written from a callback on this one comes
      # through as it is.
      rescue Recorder::RevisionNotSaved
        raise
      # Re-raised as an error Active Record's save does not rescue, so the save
      # fails, whichever method it was made with. The error names this revision
      # even when a callback on it raised about another record.
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        raise Recorder::RevisionNotSaved.new("Recorder could not write the revision: #{e.message}", revision)
      end

      private

      # A revision is dated by the request that made the change, or else today
      # in the application's time zone. Meta is read through the store, which
      # calls a Proc set as meta. This runs inside `record`, so an error from the
      # Proc fails the save as a revision that cannot be written does.
      def params_for(params)
        store = Recorder.store
        store.params.merge(meta: store.meta).merge(params).tap do |merged|
          merged[:action_date] = merged[:action_date].presence || Date.current
        end
      end
    end
  end
end
