# frozen_string_literal: true

# Join between a shift and an extra show it covers (beyond its own `source`),
# used only when several show-based shifts are merged into one.
class ShiftShow < ApplicationRecord
  belongs_to :shift
  belongs_to :show
end
