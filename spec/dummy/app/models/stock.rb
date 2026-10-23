# frozen_string_literal: true

# Declares the association `Listing` names. Shares the `securities` table.
class Stock < Listing
  self.table_name = 'securities'
  self.inheritance_column = nil

  belongs_to :issuer, class_name: 'Security', foreign_key: :guard_id, optional: true, inverse_of: false
end
