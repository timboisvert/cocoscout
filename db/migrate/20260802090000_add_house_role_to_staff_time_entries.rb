# frozen_string_literal: true

# Hours always carry a role: pay rates are a property of the work (the house
# role), not the person — someone bartends at $13/hr and works the house at
# $20/hr. Shift-backed entries get their role from the shift; this column lets
# manual (self-logged) entries carry one too, so every entry can be priced at
# the right role rate instead of silently falling back to the person's default.
class AddHouseRoleToStaffTimeEntries < ActiveRecord::Migration[8.1]
  def up
    add_reference :staff_time_entries, :house_role, null: true, foreign_key: true

    # Backfill shift-backed entries from their shift's role.
    execute <<~SQL
      UPDATE staff_time_entries
      SET house_role_id = shifts.house_role_id
      FROM shift_assignments
      JOIN shifts ON shifts.id = shift_assignments.shift_id
      WHERE staff_time_entries.shift_assignment_id = shift_assignments.id
        AND staff_time_entries.house_role_id IS NULL
    SQL
  end

  def down
    remove_reference :staff_time_entries, :house_role, foreign_key: true
  end
end
