module Recorder
  module Strategy
    class SyncSave
      def initialize(_opts = {})
      end

      def persist(item, params)
        item.revisions.create(params)
      end

      def finalize!
      end
    end
  end
end