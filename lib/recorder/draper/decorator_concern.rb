module Recorder
  module Draper
    module DecoratorConcern
      def self.included(base)
        base.decorates_association :item
      end

      def item_changeset
        return @item_changeset if defined?(@item_changeset)

        @item_changeset ||= self.changeset_klass(self.item.source).new(self.item, source.data['changes'])
      end

      def changed_associations
        source.data['associations'].keys
      end

      def association_changeset(name)
        association = self.item.send(name)
        # association = association.source if association.decorated?

        self.changeset_klass(association).new(association, source.data['associations'].fetch(name.to_s).try(:fetch, 'changes'))
      end

    protected

      def changeset_klass(object)
        klass = object.decorated? ? object.source.class : object.class
        klass = klass.base_class
        klass = "#{klass}Changeset"

        klass = klass.constantize rescue nil
        klass.present? ? klass : Recorder::Changeset
      end
    end
  end
end
