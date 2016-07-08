module Recorder
  class Tape
    attr_reader :item

    def initialize(item)
      @item = item;
    end

    def changes_for(event)
      changes = case event.to_sym
      when :create
        self.sanitize_attributes(self.item.attributes)
      when :update
        self.sanitize_attributes(self.item.previous_changes)
      when :destroy
        self.sanitize_attributes(self.item.previous_changes)
      else
        raise ArgumentError
      end

      changes.any? ? { :changes => changes } : {}
    end

    def record_create
      data = self.changes_for(:create)

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
      # data = {
      #   :changes => self.sanitize_attributes(self.item.previous_changes)
      # }

      data = self.changes_for(:update)

      associations = self.parse_associations_attributes(:update)
      data.merge!(:associations => self.parse_associations_attributes(:update)) if associations.present?

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

      self.item.revisions.create(params)
    end

    def sanitize_attributes(attributes = {})
      if self.item.respond_to?(:recorder_options) && self.item.recorder_options[:except].present?
        except = Array.wrap(self.item.recorder_options[:except])
        attributes.symbolize_keys.except(*except)
      else
        attributes
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
              end

              # if object.present? && self.sanitize_attributes(object.previous_changes).any?
              #   hash[reflection.name] = {
              #     :changes => self.sanitize_attributes(object.previous_changes)
              #   }
              # end
            end
          end

          hash
        end
      end
    end
  end
end
