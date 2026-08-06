# frozen_string_literal: true

# The per-show coverage opt-out was one blanket switch; a show that skips the
# booth tech but still needs a door person couldn't say so. It becomes a list
# of exempted role ids per show, toggled role by role from the show panel.
# (The boolean never shipped beyond dev, so nothing to carry over.)
class PerRoleStaffingCoverageExemptions < ActiveRecord::Migration[8.1]
  def change
    remove_column :shows, :staffing_coverage_exempt, :boolean, default: false, null: false
    add_column :shows, :staffing_coverage_exempt_role_ids, :jsonb, default: [], null: false
  end
end
