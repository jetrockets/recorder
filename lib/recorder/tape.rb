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
        self.sanitize_attributes(self.item.changes)
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
      data.merge!(:associations => associations_attributes) if associations_attributes.present?

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
      data.merge!(:associations => associations_attributes) if associations_attributes.present?

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
        ignore = Array.wrap(self.item.recorder_options[:ignore])
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
                hash[reflection.name] =  changes if changes.any?
                object.instance_variable_set(:@recorder_dirty, false)
              end
            end
          end

          hash
        end
      end
    end
  end
end
