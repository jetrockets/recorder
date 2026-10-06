# frozen_string_literal: true

class Security < ApplicationRecord
  include ::Recorder::Observer

  self.inheritance_column = nil

  # Exercises the `associations:` recording option.
  belongs_to :guard, class_name: 'Security', optional: true
  has_many :wards, class_name: 'Security', foreign_key: :guard_id, inverse_of: :guard

  recorder
end
