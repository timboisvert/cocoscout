# frozen_string_literal: true

class AddGapAfterAcknowledgedUntilToShifts < ActiveRecord::Migration[8.1]
  def change
    # When set, the user has confirmed the gap between this shift and the next
    # same-role shift starting at this timestamp is intentional. If the next
    # shift's starts_at changes, the value won't match anymore and the gap
    # warning reappears automatically.
    add_column :shifts, :gap_after_acknowledged_until, :datetime
  end
end
