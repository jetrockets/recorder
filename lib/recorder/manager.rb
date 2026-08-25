# frozen_string_literal: true

module Recorder
  module Manager
    def recorder_disabled!
      Recorder.store.recorder_disabled!
      return unless block_given?

      begin
        yield
      ensure
        Recorder.store.recorder_enabled!
      end
    end

    def recorder_enabled!
      Recorder.store.recorder_enabled!
    end
  end
end
