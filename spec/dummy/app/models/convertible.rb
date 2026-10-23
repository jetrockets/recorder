# frozen_string_literal: true

# An STI subclass declaring an association that its siblings do not have.
class Convertible < Instrument
  belongs_to :underlying, class_name: 'Instrument', foreign_key: :guard_id, optional: true, inverse_of: false
end
