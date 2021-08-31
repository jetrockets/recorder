module Recorder
  class Tape
    module ClassMethods
      def record(params, options = {})
        params = params_for(params)

        if async?(options)
          record_async(params, options)
        else
          Recorder::Revision.create(params)
        end
      end

      private

      def params_for(params)
        Recorder.store.merge({
          action_date: Date.today,
          **params
        })
      end

      def async?(options)
        options[:async].nil? ? Recorder.config.async : options[:async]
      end

      def record_async(params, options)
        Recorder::Sidekiq::RevisionsWorker.perform_in(
          options[:delay] || 2.seconds,
          params
        )
      end
    end
  end
end
