# frozen_string_literal: true

# Exercises the `associations:` option end to end.
class Ledger < ApplicationRecord
  self.table_name = 'securities'
  self.inheritance_column = nil

  include ::Recorder::Observer

  belongs_to :guard, class_name: 'Ledger', optional: true

  recorder associations: {guard: {only: %i[name]}}
end
