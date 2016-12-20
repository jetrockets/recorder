module Recorder
  module Sidekiq
    class RevisionsWorker
      include ::Sidekiq::Worker

      sidekiq_options Recorder.config.sidekiq_options

      def perform(klass, id, params)
        object = klass.constantize.find_by(:id => id)
        object.revisions.create(params) if object.present?
      end
    end
  end
end
