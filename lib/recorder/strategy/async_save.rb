module Recorder
  module Strategy
    class AsyncSave
      def initialize(_opts = {})
      end

      def persist(item, params)
        item.revisions.create_async(params)
      end

      def finalize!
      end
    end
  end
end