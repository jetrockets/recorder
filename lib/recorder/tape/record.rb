# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      # The primary key types each kind of `item_id` column stores unchanged,
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
        fit_item_key(revision)
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
      # no model with a table is not checked.
      def fit_item_key(revision)
        model = item_model(revision)
        return if model.nil?

        key = model.primary_key
        unsupported_key("#{model.name} has no single-column primary key") unless key.is_a?(String)

        key_type = model.type_for_attribute(key)
        column = revision.class.columns_hash['item_id']
        unless ITEM_KEY_TYPES.fetch(item_id_kind(column), []).include?(key_type.type)
          unsupported_key(
            "#{model.name}'s primary key #{key} (#{key_type.type || key_type.class.name || "a custom type"}) " \
            "does not fit #{revision.class.table_name}.item_id (#{column.sql_type})"
          )
        end
      end

      def unsupported_key(problem)
        raise Recorder::UnsupportedPrimaryKey,
          "#{problem}, so Recorder cannot write its revisions. See \"Primary keys\" in the Recorder README."
      end

      def item_model(revision)
        item_type = revision.item_type.to_s
        model = revision.class.polymorphic_class_for(item_type)
        model if model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class? && model.table_exists?
      # A NameError about `item_type` itself means it names no constant, or is
      # not a constant name. Any other comes from loading the model.
      rescue NameError => e
        raise unless e.name.nil? || item_type == e.name.to_s || item_type.split('::').include?(e.name.to_s)
      end

      # The column's type, or nothing for a `character(n)` column, which pads
      # shorter keys so that `revision.item` does not find them.
      def item_id_kind(column)
        column.type unless column.sql_type.match?(/\Acharacter(?! varying)/)
      end
    end
  end
end
