# frozen_string_literal: true

class Security < ApplicationRecord
  include ::Recorder::Observer
end
