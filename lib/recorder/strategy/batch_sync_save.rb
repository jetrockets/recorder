module Recorder
  module Strategy
    class BatchSyncSave
      def initialize(opts)
        @batch_size = opts[:batch_size] || 10
        @revisions = []
      end

      def persist(item, params)
        params[:item_type] = item.class.name
        params[:item_id] = item.id
        @revisions << ::Recorder::Revision.new(params)
        save_to_db if @revisions.size >= @batch_size
      end

      def finalize!
        save_to_db
      end

      private

      def save_to_db
        revisions = @revisions.dup
        @revisions = []
        if defined? ActiveRecord::Import
          ::Recorder::Revision.import(revisions)
        else
          ActiveRecord::Base.transaction do
            revisions.each(&:save)
          end
        end
      end
    end
  end
end