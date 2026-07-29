# frozen_string_literal: true

# Drop the per-role "start early / end late" offsets. Shifts now run for the
# show's own hours — any early-in/late-out is baked into the show times and the
# contract, so the offsets were unused and confusing.
class RemoveOffsetMinutesFromHouseRoles < ActiveRecord::Migration[8.1]
  def change
    remove_column :house_roles, :default_start_offset_minutes, :integer, default: -60, null: false
    remove_column :house_roles, :default_end_offset_minutes, :integer, default: 60, null: false
  end
end
