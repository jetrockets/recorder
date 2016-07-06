module Recorder
  module Draper
    module DecoratorConcern
      def self.included(base)
        base.decorates_association :item
      end

      def item_human_attribute_name(attribute)
        self.item.source.class.human_attribute_name(attribute)
      end
    end
  end
end
