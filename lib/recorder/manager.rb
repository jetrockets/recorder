# frozen_string_literal: true

module Recorder
  module Manager
    # Without a block, disables recording until `recorder_enabled!`. With one,
    # disables it for the block and then restores the state it found.
    def recorder_disabled!
      was_enabled = Recorder.store.recorder_enabled?
      Recorder.store.recorder_disabled!
      return unless block_given?

      begin
        yield
      ensure
        if was_enabled
          Recorder.store.recorder_enabled!
        else
          Recorder.store.recorder_disabled!
        end
      end
    end

    def recorder_enabled!
      Recorder.store.recorder_enabled!
    end
  end
end
