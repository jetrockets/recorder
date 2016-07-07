module Recorder
  class Tape
    attr_reader :item

    def initialize(item)
      @item = item;
    end

    def record_create
      data = {
        :changes => self.sanitize_attributes(self.item.attributes)
      }

      # changes.merge!(self.parse_associations_attributes)

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
      data = {
        :changes => self.sanitize_attributes(self.item.previous_changes)
      }

      associations = self.parse_associations_attributes
      data.merge!(:associations => self.parse_associations_attributes) if associations.any?

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
      attributes.symbolize_keys.except(self.item.recorder_options[:except])
    end

    def parse_associations_attributes
      if self.item.recorder_options[:associations].any?
        self.item.recorder_options[:associations].inject({}) do |hash, association|
          reflection = self.item.class.reflect_on_association(association)
          if reflection.present?
            if reflection.collection?

            else
              object = self.item.send(association)

              if object.present? && self.sanitize_attributes(object.previous_changes).any?
                hash[reflection.name] = {
                  :changes => self.sanitize_attributes(object.previous_changes)
                }
              end
            end
          end

          hash
        end
      end
    end
  end
end
