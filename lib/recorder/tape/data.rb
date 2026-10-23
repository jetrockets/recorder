# frozen_string_literal: true

require 'concurrent/map'

module Recorder
  class Tape
    class Data
      # The `associations:` warnings already logged, by class name and message.
      WARNED = Concurrent::Map.new

      attr_reader :item

      def initialize(item)
        @item = item
      end

      def data_for(event, options = {})
        data = {
          **attributes_for(event, options),
          **changes_for(event, options),
          **associations_for(event, options)
        }

        record_changed?(data, event) ? data : {}
      end

      def attributes_for(_event, options)
        {attributes: sanitize_attributes(persisted_attributes, options)}
      end

      def self.validate_changes_option!(callback)
        return if callback.nil? || callback.is_a?(Proc) || callback.is_a?(Symbol) || callback.is_a?(String)

        raise ArgumentError, "`changes:` expects a Proc or a method name, got #{callback.inspect}"
      end

      def changes_for(event, options)
        changes = attribute_changes_for(event, options).merge(custom_changes_for(event, options))

        changes.present? ? {changes: changes} : {}
      end

      def associations_for(event, options)
        return {} if event.to_sym == :update

        associations = parse_associations_attributes(event, options)

        associations.present? ? {associations: associations} : {}
      end

      private

      # The values the record last loaded or saved; one that was never saved
      # has only its in-memory values.
      def persisted_attributes
        return item.attributes if item.new_record?

        item.attributes.merge(item.attributes_in_database)
      end

      # `destroy` leaves `saved_changes` holding the record's last save.
      def attribute_changes_for(event, options)
        return {} if event.to_sym == :destroy

        sanitize_attributes(item.saved_changes, options)
      end

      def custom_changes_for(event, options)
        callback = options[:changes]
        return {} unless callback

        self.class.validate_changes_option!(callback)

        changes = callback.is_a?(Proc) ? item.instance_exec(event, &callback) : item.send(callback, event)

        changes ? Hash(changes).symbolize_keys : {}
      end

      def sanitize_attributes(attributes, options)
        if options[:only].present?
          only = wrap_options(options[:only])
          attributes.symbolize_keys.slice(*only)
        elsif options[:ignore].present?
          ignore = wrap_options(options[:ignore])
          attributes.symbolize_keys.except(*ignore)
        else
          attributes.symbolize_keys.except(*Recorder.config.ignore)
        end
      end

      def wrap_options(values)
        Array.wrap(values).map(&:to_sym)
      end

      def parse_associations_attributes(event, options)
        return unless options[:associations]

        options[:associations].each_with_object({}) do |(association, options), hash|
          name, data = parse_association(event, association, options)

          hash[name] = data if data
        end
      end

      # Logs a warning for a collection, and for a name that no class in the
      # item's hierarchy declares, and skips both.
      def parse_association(event, association, options)
        reflection = item.class.reflect_on_association(association)

        if reflection.nil?
          unless association_in_hierarchy?(association)
            warn_unrecordable("names #{association.inspect}, which is not an association of #{item.class}")
          end
        elsif reflection.collection?
          warn_unrecordable("names the collection #{association.inspect} of #{item.class}; " \
            'only singular associations are recorded')
        elsif (object = item.send(association)) && !unsaved_on_destroy?(object, event)
          [reflection.name, Recorder::Tape::Data.new(object).attributes_for(event, options || {})]
        end
      end

      # A record that was never saved has no row for a destroy to describe; on
      # create, Rails saves it in the same transaction.
      def unsaved_on_destroy?(object, event)
        event.to_sym == :destroy && object.new_record?
      end

      # Subclasses inherit `associations:`, so an entry can name an association
      # that only a sibling declares.
      def association_in_hierarchy?(association)
        declared_in = item.class.recorder_declared_in || item.class

        [declared_in, *declared_in.descendants].any? { |klass| klass.reflect_on_association(association) }
      end

      # Once per class and message in a process.
      def warn_unrecordable(message)
        return unless WARNED.put_if_absent([item.class.name, message], true).nil?

        item.class.logger&.warn("Recorder: `associations:` #{message}")
        nil
      end

      def record_changed?(data, event)
        event.to_sym != :update || data[:changes]
      end
    end
  end
end
