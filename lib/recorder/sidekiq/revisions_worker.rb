module Recorder
  module Sidekiq
    class RevisionsWorker
      include ::Sidekiq::Worker

      sidekiq_options Recorder.config.sidekiq_options

      def perform(klass, id, params)
        klass.constantize.find(id).revisions.create(params)
      end
    end
  end
end
