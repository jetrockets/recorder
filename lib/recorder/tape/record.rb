# frozen_string_literal: true

module Recorder
  class Tape
    module Record
      def record(params, options = {})
        return if Recorder.store.recorder_disabled?

        params = params_for(params)

        if async?(options)
          record_async(params, options)
        else
          Recorder::Revision.create(params)
        end
      end

      private

      def params_for(params)
        Recorder.store.params.merge({
          action_date: Date.today,
          **params
        })
      end

      def async?(options)
        options[:async].nil? ? Recorder.config.async : options[:async]
      end

      def record_async(params, options)
        params[:data] = params[:data].to_json
        params[:action_date] = params[:action_date].to_s

        Recorder::Sidekiq::RevisionsWorker.perform_in(
          options[:delay] || 2.seconds,
          params.stringify_keys
        )
      end
    end
  end
end
