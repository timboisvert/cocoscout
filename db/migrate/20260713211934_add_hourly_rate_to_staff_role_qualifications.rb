# frozen_string_literal: true

class AddHourlyRateToStaffRoleQualifications < ActiveRecord::Migration[8.1]
  def change
    # Per-role pay rate: what this staff member earns when working this role.
    # Nil falls back to the member's default hourly_rate_cents.
    add_column :staff_role_qualifications, :hourly_rate_cents, :integer
  end
end
