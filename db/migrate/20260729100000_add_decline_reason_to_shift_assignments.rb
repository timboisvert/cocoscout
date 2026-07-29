# frozen_string_literal: true

# Lets a staff member say "I can't make it" on an assigned shift, with an
# optional note. `declined_at` already exists; this adds the reason. No auto-
# offering to others — managers just see who can't make it.
class AddDeclineReasonToShiftAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_assignments, :decline_reason, :string
  end
end
