# frozen_string_literal: true

class Security < ApplicationRecord
  include ::Recorder::Observer

  self.inheritance_column = nil
end
