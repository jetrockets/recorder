# frozen_string_literal: true

require 'request_store'

module Recorder
  class Store
    def params
      store[:params]
    end

    # The request's meta. A Proc set as meta is called the first time this is
    # read, and its value replaces it.
    def meta
      value = params[:meta]
      value.is_a?(Proc) ? resolve_meta(value) : value
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

    private

    # Meta is unset while the Proc runs, so a revision written from inside it
    # carries none. If the Proc fails, it is put back for the next revision to
    # call again.
    def resolve_meta(pending)
      params.delete(:meta)
      params[:meta] = pending.call
    ensure
      params[:meta] = pending unless params.key?(:meta)
    end

    def store
      RequestStore.store[:recorder] ||= {
        enabled: true,
        params: {}
      }
    end
  end
end
