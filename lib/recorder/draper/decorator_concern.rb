module Recorder
  module Draper
    module DecoratorConcern
      def self.included(base)
        base.decorates_association :item
      end

      def item_changeset
        @item_changeset ||= Recorder::Changeset.new(self.item.source, source.data['changes'])
      end

      def changed_associations
        source.data['associations'].keys#.map{ |association| self.item_human_attribute_name(association) }
      end

      def association_changeset(name)
        association = self.item.send(name)
        association = association.source if association.decorated?

        Recorder::Changeset.new(association, source.data['associations'].fetch(name.to_s).try(:fetch, 'changes'))
      end
    end
  end
end
