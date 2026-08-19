# frozen_string_literal: true

# Work time regions ("day parts") an organization turns on for staffing —
# Morning / Afternoon / Evening and finer slices from a fixed catalog — replace
# the hard-coded "before 5pm is Afternoon, from 5pm is Evening" split.
# organizations.staffing_day_parts holds the chosen keys; a person's
# unavailability mark names one region key (or the whole day) instead of
# holding a fixed enum.
#
# The old integer `scope` column stays until the next deploy (the model
# ignores it) so a still-running old container never reads a missing column;
# drop it in a follow-up migration.
class AddStaffingDayParts < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :staffing_day_parts, :jsonb, default: [], null: false
    add_column :staff_unavailabilities, :day_part_key, :string

    # all_day (0) → nil; day_shifts (1) → "afternoon" (the region it was
    # labelled); evening_shifts (2) → "evening". Both are on by default.
    execute <<~SQL
      UPDATE staff_unavailabilities SET day_part_key = 'afternoon' WHERE scope = 1;
      UPDATE staff_unavailabilities SET day_part_key = 'evening' WHERE scope = 2;
    SQL
  end

  def down
    execute <<~SQL
      UPDATE staff_unavailabilities SET scope = CASE WHEN day_part_key IS NULL THEN 0 WHEN day_part_key = 'evening' THEN 2 ELSE 1 END;
    SQL
    remove_column :staff_unavailabilities, :day_part_key
    remove_column :organizations, :staffing_day_parts
  end
end
