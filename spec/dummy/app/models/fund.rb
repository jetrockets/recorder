# frozen_string_literal: true

# Lacks the association `Listing` names. Shares the `securities` table.
class Fund < Listing
  self.table_name = 'securities'
  self.inheritance_column = nil
end
