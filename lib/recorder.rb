require 'recorder/version'
require 'recorder/changeset'
require 'recorder/observer'
require 'recorder/rails/controller_concern'

require 'request_store'

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

    # Returns a boolean indicating whether "protected attibutes" should be
    # configured, e.g. attr_accessible.
    def active_record_protected_attributes?
      @active_record_protected_attributes ||= !!defined?(ProtectedAttributes)
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

if defined?(Draper)
  require 'recorder/draper/decorator_concern'
end

require 'recorder/revision'
