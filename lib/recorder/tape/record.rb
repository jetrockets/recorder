# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      # The primary key types each type of `item_id` column stores unchanged,
      # so that `revisions` finds the rows again.
      ITEM_KEY_TYPES = {
        integer: %i[integer],
        uuid: %i[uuid],
        string: %i[integer uuid string text],
        text: %i[integer uuid string text]
      }.freeze
      private_constant :ITEM_KEY_TYPES

      # @raise [Recorder::UnsupportedPrimaryKey] if `item_id` cannot hold the
      #   primary key of the model `item_type` names
      def record(params)
        return unless Recorder.recording?

        revision = Recorder::Revision.new(params_for(params))
        check_item_key(revision)
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
      # in the application's time zone.
      def params_for(params)
        Recorder.store.params.merge(params).tap do |merged|
          merged[:action_date] = merged[:action_date].presence || Date.current
        end
      end

      # Checks the key of the model `revision.item` loads, the base class of an
      # STI subclass, against the `item_id` column. An `item_type` that names
      # no model is not checked.
      def check_item_key(revision)
        model = item_model(revision.item_type)
        problem = model && item_key_problem(model)
        return if problem.nil?

        raise Recorder::UnsupportedPrimaryKey,
          "#{problem}, so Recorder cannot write its revisions. See \"Primary keys\" in the Recorder README."
      end

      def item_key_problem(model)
        key = model.primary_key
        return "#{model.name} has no single-column primary key" unless key.is_a?(String)

        key_type = model.type_for_attribute(key).type
        return if ITEM_KEY_TYPES.fetch(Recorder::Revision.type_for_attribute('item_id').type, []).include?(key_type)

        "#{model.name}'s #{key_type} primary key does not fit #{Recorder::Revision.table_name}.item_id " \
          "(#{Recorder::Revision.columns_hash["item_id"].sql_type})"
      end

      def item_model(item_type)
        model = Recorder::Revision.polymorphic_class_for(item_type.to_s)
        model if model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class?
      rescue NameError
        nil
      end
    end
  end
end
