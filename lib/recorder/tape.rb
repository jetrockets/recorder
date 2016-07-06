module Recorder
  class Tape
    attr_reader :item, :options

    def initialize(item, options = {})
      @item = item
      @options = options
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
      # attributes.symbolize_keys.delete_if{ |key, value|  [:created_at, :updated_at, :delta].include?(key) || (value[0] == value[1]) }
      attributes.symbolize_keys.except(:created_at, :updated_at, :delta)
    end

    def parse_associations_attributes
      if self.options[:associations].any?
        self.options[:associations].inject({}) do |hash, association|
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
