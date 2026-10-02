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

      # A revision is dated by the request that made the change, or else today
      # in the application's time zone.
      def params_for(params)
        Recorder.store.params.merge(params).tap do |merged|
          merged[:action_date] ||= Date.current
        end
      end

      def async?(options)
        options[:async].nil? ? Recorder.config.async : options[:async]
      end

      # Sidekiq accepts only JSON-native job arguments. `data` is serialised
      # ahead of the round trip so it survives as a string for the worker to
      # parse back; everything else is normalised by the round trip itself.
      def record_async(params, options)
        params[:data] = params[:data].to_json

        Recorder::Sidekiq::RevisionsWorker.perform_in(
          options[:delay] || 2.seconds,
          JSON.parse(params.to_json)
        )
      end
    end
  end
end
