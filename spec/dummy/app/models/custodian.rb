# frozen_string_literal: true

# Declares `recorder` before the `has_one` it names, so Rails saves the child
# after the create revision is written. Shares the `securities` table.
class Custodian < ApplicationRecord
  include ::Recorder::Observer

  self.table_name = 'securities'
  self.inheritance_column = nil

  recorder associations: {ward: {only: %i[name]}}

  has_one :ward, class_name: 'Security', foreign_key: :guard_id, inverse_of: false
end
