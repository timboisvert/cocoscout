# frozen_string_literal: true

# Two scheduling-page changes Tim asked for:
# - The "gap in coverage — OK?" acknowledgment feature is gone (nobody wants
#   to be nagged about intentional gaps), so its column goes with it.
# - New org toggle for the show-role coverage assistant: when on, the shows
#   listed under each staffing day flag any show missing coverage for a
#   show-specific role (booth tech etc.), naming the uncovered roles.
class StaffingSchedulingCleanup < ActiveRecord::Migration[8.1]
  def change
    remove_column :shifts, :gap_after_acknowledged_until, :datetime
    add_column :organizations, :alert_uncovered_show_roles, :boolean, default: false, null: false
  end
end
