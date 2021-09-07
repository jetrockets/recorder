# frozen_string_literal: true

module Recorder
  module Sidekiq
    class RevisionsWorker
      include ::Sidekiq::Worker

      sidekiq_options Recorder.config.sidekiq_options

      def perform(params)
        Recorder::Revision.create(params)
      end
    end
  end
end
