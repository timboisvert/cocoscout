# frozen_string_literal: true

# Per-show opt-out of the show-role coverage assistant: some shows genuinely
# don't need the show-specific staffing roles (a rental running its own booth,
# a stripped-down matinee), and flagging them forever is just noise.
class AddStaffingCoverageExemptToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :staffing_coverage_exempt, :boolean, default: false, null: false
  end
end
