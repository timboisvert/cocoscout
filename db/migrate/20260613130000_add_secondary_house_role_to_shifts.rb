# frozen_string_literal: true

# Lets a single shift cover a second role ("doubling up"), e.g. the bartender
# who is also the manager that night — one shift, one assignment, two duties.
class AddSecondaryHouseRoleToShifts < ActiveRecord::Migration[8.1]
  def change
    add_reference :shifts, :secondary_house_role, null: true,
                  foreign_key: { to_table: :house_roles }
  end
end
