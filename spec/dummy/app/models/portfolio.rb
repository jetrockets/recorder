# frozen_string_literal: true

# Names a collection in `associations:`, which Recorder refuses. Shares the
# `securities` table.
class Portfolio < ApplicationRecord
  include ::Recorder::Observer

  self.table_name = 'securities'
  self.inheritance_column = nil

  has_many :holdings, class_name: 'Security', foreign_key: :guard_id, inverse_of: false

  recorder associations: {holdings: {only: %i[name]}}
end
