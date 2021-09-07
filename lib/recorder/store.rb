# frozen_string_literal: true

require 'request_store'

module Recorder
  class Store
    def params
      store[:params]
    end

    def recorder_enabled!
      store[:enabled] = true
    end

    def recorder_disabled!
      store[:enabled] = false
    end

    def recorder_enabled?
      store[:enabled]
    end

    def recorder_disabled?
      !store[:enabled]
    end

    private

    def store
      RequestStore.store[:recorder] ||= {
        enabled: true,
        params: {}
      }
    end
  end
end
