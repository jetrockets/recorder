require 'recorder/version'
require 'recorder/observer'
require 'recorder/rails/controller'

module Recorder
  class << self
    # Sets Recorder information from the controller.
    # @api public
    def info=(hash)
      self.store.merge!(hash)
    end

    # Sets Recorder meta information.
    # @api public
    def meta=(hash)
      self.store[:meta] = hash
    end

    # Thread-safe hash to hold Recorder's data.
    # @api private
    def store
      RequestStore.store[:recorder] ||= { }
    end

    def version
      VERSION::STRING
    end
  end
end
