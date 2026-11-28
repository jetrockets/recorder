# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      # Returns `true`, or `nil` while recording is off.
      # @api private
      def record(params)
        true if write_revision(params)
      end

      # The one place a revision is built and saved. Returns the saved
      # revision, or `nil` while recording is off.
      # @api private
      def write_revision(params)
        return unless Recorder.recording?

        revision = Recorder::Revision.new(params_for(params))
        revision.save!
        revision
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

      # The columns that name a revision's item. `item_type` is the value
      # `has_many :revisions` looks rows up by: the base class of an STI
      # subclass.
      # @api private
      def item_columns(item)
        {item_type: item.class.polymorphic_name, item_id: item.id}
      end

      # The names of the revisions table's columns, each with the Active Record
      # type that casts a value written to it.
      # @api private
      def revision_columns
        Recorder::Revision.column_names.index_with { |name| Recorder::Revision.type_for_attribute(name) }
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
