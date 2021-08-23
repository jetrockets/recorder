module Recorder
  class Tape
    attr_reader :item

    def initialize(item)
      @item = item;

      item.instance_variable_set(:@recorder_dirty, true)
    end

    def record_create
      data = data_for(:create, recorder_options)

      if data.any?
        record(
          Recorder.store.merge({
            event: :create,
            data: data
          })
        )
      end
    end

    def record_update
      data = data_for(:update, recorder_options)

      if data.any?
        record(
          Recorder.store.merge({
            event: :update,
            data: data
          })
        )
      end
    end

    def record_destroy
      data = data_for(:destroy, recorder_options)

      if data.any?
        record(
          Recorder.store.merge({
            event: :destroy,
            data: data
          })
        )
      end
    end

    def data_for(event, options = {})
      {
        **attributes_for(event, options),
        **changes_for(event, options),
        **associations_for(event, options)
      }
    end

  protected

    def recorder_options
      item.respond_to?(:recorder_options) ? item.recorder_options : {}
    end

    def attributes_for(event, options)
      { attributes: sanitize_attributes(item.attributes, options) }
    end

    def changes_for(event, options)
      changes =
        case event.to_sym
        when :update
          sanitize_attributes(item.saved_changes, options)
        end

      changes.present? ? { changes: changes } : {}
    end

    def associations_for(event, options)
      associations = parse_associations_attributes(event, options)

      associations.present? ? { associations: associations } : {}
    end

    def record(params)
      params.merge!(action_date: Date.today)

      puts "!!!!!!!"
      puts params

      if item.recorder_options[:async]
        record_async(item, params)
      else
        Recorder::Revision.create(
          item: item,
          **params
        )
      end
    end

    def record_async(item, params)
      Recorder::Sidekiq::RevisionsWorker.perform_in(
        item.recorder_options[:delay] || 2.seconds,
        item.class.to_s,
        item.id,
        params
      )
    end

    def sanitize_attributes(attributes = {}, options)
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

      options[:associations].inject({}) do |hash, (association, options)|
        name, data = parse_association(event, association, options)

        hash[name] = data if data.any?
        hash
      end
    end

    def parse_association(event, association, options)
      reflection = item.class.reflect_on_association(association)

      if reflection.present?
        if reflection.collection?

        elsif object = item.send(association)
          data = Recorder::Tape.new(object).data_for(event, options || {})
          object.instance_variable_set(:@recorder_dirty, false)

          [reflection.name, data]
        end
      end
    end
  end
end
