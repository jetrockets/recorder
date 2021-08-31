module Recorder
  module Manager
    def recorder_disabled!
      Recorder.store.recorder_disabled!

      if block_given?
        yield
        Recorder.store.recorder_enabled!
      end
    end

    def recorder_enabled!
      Recorder.store.recorder_enabled!
    end
  end
end
