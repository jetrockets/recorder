# frozen_string_literal: true

# STI base for the per-model option specs. `Security` cannot serve here: it sets
# `inheritance_column = nil`, which switches STI off. Shares the `securities`
# table, which already carries a `type` column.
class Instrument < ApplicationRecord
  self.table_name = 'securities'

  include ::Recorder::Observer

  belongs_to :guard, class_name: 'Instrument', optional: true

  recorder ignore: %i[identifier]
end
