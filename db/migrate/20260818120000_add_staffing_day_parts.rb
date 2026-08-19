# frozen_string_literal: true

# Work time regions ("day parts") an organization declares for staffing —
# Morning / Afternoon / Evening with the hours each covers — replace the
# hard-coded "before 5pm is Afternoon, from 5pm is Evening" split. A person's
# unavailability mark names one region (or the whole day) instead of holding a
# fixed enum.
#
# The old integer `scope` column stays until the next deploy (the model
# ignores it) so a still-running old container never reads a missing column;
# drop it in a follow-up migration.
class AddStaffingDayParts < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :staffing_day_parts, :jsonb, default: [], null: false
    add_column :staff_unavailabilities, :day_part_key, :string

    # all_day (0) → nil; day_shifts (1) → the region that was labelled
    # "Afternoon"; evening_shifts (2) → "evening". These keys match the
    # defaults an org gets before declaring its own regions.
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
