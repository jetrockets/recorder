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

      def changes_for(event, options)
        changes = sanitize_attributes(item.saved_changes, options)

        changes.present? ? {changes: changes} : {}
      end

      def associations_for(event, options)
        associations = parse_associations_attributes(event, options)

        associations.present? ? {associations: associations} : {}
      end

      private

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

          hash[name] = data if data&.any?
        end
      end

      def parse_association(event, association, options)
        reflection = item.class.reflect_on_association(association)

        if reflection.present?
          if reflection.collection?

          elsif (object = item.send(association))
            data = Recorder::Tape::Data.new(object).data_for(event, options || {})

            [reflection.name, data]
          end
        end
      end

      def record_changed?(data, event)
        event.to_sym != :update || data[:changes] || associations_changed?(data)
      end

      def associations_changed?(data)
        return if data[:associations].nil?

        data[:associations].any? { |name, association| association[:changes] }
      end
    end
  end
end
