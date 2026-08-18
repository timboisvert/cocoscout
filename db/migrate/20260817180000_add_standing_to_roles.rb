# frozen_string_literal: true

# A standing role ("Show role" in the UI: the MC, Stage Kitten ×2) is cast per
# show like any role but sits outside an act-based lineup — it isn't numbered
# in the running order, isn't an act for pay, and may hold several people.
# The flag is idle in a role-based production.
class AddStandingToRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :roles, :standing, :boolean, null: false, default: false
  end
end
