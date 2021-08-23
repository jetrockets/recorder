module Recorder
  module Sidekiq
    class RevisionsWorker
      include ::Sidekiq::Worker

      sidekiq_options Recorder.config.sidekiq_options

      def perform(klass, id, params)
        Recorder::Revision.create(
          item_type: klass,
          item_id: id,
          **params
        )
      end
    end
  end
end
