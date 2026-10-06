# frozen_string_literal: true

module Recorder
  class Tape
    class Data
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
        {attributes: sanitize_attributes(item.attributes, options)}
      end

      def self.validate_changes_option!(callback)
        return if callback.nil? || callback.is_a?(Proc) || callback.is_a?(Symbol) || callback.is_a?(String)

        raise ArgumentError, "`changes:` expects a Proc or a method name, got #{callback.inspect}"
      end

      def changes_for(event, options)
        changes = sanitize_attributes(item.saved_changes, options).merge(custom_changes_for(event, options))

        changes.present? ? {changes: changes} : {}
      end

      # Raises ArgumentError on every event, update included, when
      # `associations:` names a collection or something that is not an
      # association.
      def associations_for(event, options)
        reflections = association_reflections(options)
        return {} if event.to_sym == :update

        associations = parse_associations_attributes(reflections)

        associations.present? ? {associations: associations} : {}
      end

      private

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

      # Each association named in `associations:`, as its reflection and its own options.
      def association_reflections(options)
        return [] unless options[:associations]

        options[:associations].map do |association, association_options|
          [reflection_for(association), association_options]
        end
      end

      def reflection_for(association)
        reflection = item.class.reflect_on_association(association)

        if reflection.nil?
          raise ArgumentError, "`associations:` names #{association.inspect}, which is not an association of #{item.class}"
        elsif reflection.collection?
          raise ArgumentError, "`associations:` names the collection #{association.inspect} of #{item.class}; " \
            'only singular associations are recorded'
        end

        reflection
      end

      def parse_associations_attributes(reflections)
        reflections.each_with_object({}) do |(reflection, options), hash|
          object = item.send(reflection.name)

          hash[reflection.name] = Recorder::Tape::Data.new(object).attributes_for(nil, options || {}) if object
        end
      end

      def record_changed?(data, event)
        event.to_sym != :update || data[:changes]
      end
    end
  end
end
