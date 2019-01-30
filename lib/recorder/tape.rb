module Recorder
  class Tape
    attr_reader :item

    def initialize(item)
      @item = item;

      self.item.instance_variable_set(:@recorder_dirty, true)
    end

    def changes_for(event)
      changes = case event.to_sym
      when :create
        self.sanitize_attributes(self.item.attributes)
      when :update
        self.sanitize_attributes(self.item.respond_to?(:saved_changes) ? self.item.saved_changes : self.item.changes)
      when :destroy
        self.sanitize_attributes(self.item.changes)
      else
        raise ArgumentError
      end

      changes.any? ? { :changes => changes } : {}
    end

    def record_create
      data = self.changes_for(:create)

      associations_attributes = self.parse_associations_attributes(:create)
      parse_associations_attributes_for_habtm = self.parse_associations_attributes_for_habtm(:create)

      data.merge!(:associations => associations_attributes) if associations_attributes.present?
      data.merge!(:associations_habtm => parse_associations_attributes_for_habtm) if parse_associations_attributes_for_habtm.present?

      if data.any?
        self.record(
          Recorder.store.merge({
            :event => :create,
            :data => data
          })
        )
      end
    end

    def record_update
      data = self.changes_for(:update)

      associations_attributes = self.parse_associations_attributes(:update)
      parse_associations_attributes_for_habtm = self.parse_associations_attributes_for_habtm(:update)

      data.merge!(:associations => associations_attributes) if associations_attributes.present?
      data.merge!(:associations_habtm => parse_associations_attributes_for_habtm) if parse_associations_attributes_for_habtm.present?

      if data.any?
        self.record(
          Recorder.store.merge({
            :event => :update,
            :data => data
          })
        )
      end
    end

    def record_destroy
    end

  protected

    def record(params)
      params.merge!({
        :action_date => Date.today
      })

      if self.item.recorder_options[:async]
        self.item.revisions.create_async(params)
      else
        self.item.revisions.create(params)
      end
    end

    def sanitize_attributes(attributes = {})
      if self.item.respond_to?(:recorder_options) && self.item.recorder_options[:ignore].present?
        ignore = Array.wrap(self.item.recorder_options[:ignore]).map(&:to_sym)
        attributes.symbolize_keys.except(*ignore)
      else
        attributes.symbolize_keys.except(*Recorder.config.ignore)
      end
    end

    def parse_associations_attributes(event)
      if self.item.respond_to?(:recorder_options) && self.item.recorder_options[:associations].present?
        self.item.recorder_options[:associations].inject({}) do |hash, association|
          reflection = self.item.class.reflect_on_association(association)
          if reflection.present?
            if reflection.collection?

            else
              if object = self.item.send(association)
                changes = Recorder::Tape.new(object).changes_for(event)
                hash[reflection.name] = changes if changes.any?
                object.instance_variable_set(:@recorder_dirty, false)
              end
            end
          end
          hash
        end
      end
    end


    # For use this method you need add to your model next config:
    # recorder associations_hambt: [
    #   {
    #     class: :lots,                        # -- name associations
    #     check_change: :lots_changed?,        # -- method who return true/false if habtm changes
    #     old_collection: :old_lots_collection # -- old collection
    #   }
    # ]
    #
    #
    # Example
    # Method rewrites assignment habtm ids
    #
    # def lot_ids=(ids)
    #   @lots_changed = ids != lot_ids                   #  return true/nil
    #   @old_lots_collection = lot_ids if @lots_changed  #  remembers the old collection, may be nil

    #   super(ids)
    # end
    #
    #  return true/false if habtm changes
    # def lots_changed?
    #   @lots_changed || false
    # end
    # And add attr_reade to @old_lots_collection

    def parse_associations_attributes_for_habtm(event)
      self.item.recorder_options[:associations_hambt].inject({}) do |hash, association|
        raise ArgumentError if association[:class].nil? && association[:check_change].nil? && association[:old_collection]
        reflection = self.item.class.reflect_on_association(association[:class])
        if reflection.present?
          if reflection.collection?
            if self.item.send(association[:check_change])
              changes = [self.item.send(association[:old_collection]), self.item.lot_ids]
              hash["#{association[:class]}_id".to_sym] = changes
            end
          end
        end
        hash
      end
    end
  end
end
