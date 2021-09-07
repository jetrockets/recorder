# frozen_string_literal: true

class Security < ActiveRecord::Base
  include ::Recorder::Observer
end
