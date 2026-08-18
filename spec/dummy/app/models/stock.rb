# frozen_string_literal: true

# Overrides its parent's options. Must not leak the override back up to
# `Instrument` or sideways to `Bond`.
class Stock < Instrument
  recorder only: %i[name]
end
