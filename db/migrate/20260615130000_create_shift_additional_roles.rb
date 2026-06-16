# frozen_string_literal: true

# A shift can cover more than one role with a single assignment (e.g. one person
# is the manager AND the bartender AND house staff). This replaces the single
# `secondary_house_role_id` column with a join table so any number of extra
# roles can ride on one shift.
class CreateShiftAdditionalRoles < ActiveRecord::Migration[8.1]
  def up
    create_table :shift_additional_roles do |t|
      t.references :shift, null: false, foreign_key: true
      t.references :house_role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :shift_additional_roles, [ :shift_id, :house_role_id ], unique: true,
              name: "idx_shift_additional_roles_unique"

    # Migrate the single secondary role into the new join table.
    execute <<~SQL.squish
      INSERT INTO shift_additional_roles (shift_id, house_role_id, created_at, updated_at)
      SELECT id, secondary_house_role_id, NOW(), NOW()
      FROM shifts
      WHERE secondary_house_role_id IS NOT NULL
    SQL

    remove_column :shifts, :secondary_house_role_id
  end

  def down
    add_column :shifts, :secondary_house_role_id, :bigint
    # Best-effort restore: keep the first additional role per shift.
    execute <<~SQL.squish
      UPDATE shifts SET secondary_house_role_id = sub.house_role_id
      FROM (
        SELECT DISTINCT ON (shift_id) shift_id, house_role_id
        FROM shift_additional_roles ORDER BY shift_id, id
      ) sub
      WHERE sub.shift_id = shifts.id
    SQL
    drop_table :shift_additional_roles
  end
end
