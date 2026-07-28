# frozen_string_literal: true

class AddDefaultHourlyRateToHouseRoles < ActiveRecord::Migration[8.1]
  def change
    # A role's standard pay. Seeds each staff member's per-role rate on the staff
    # screen so producers don't re-type it for everyone; still overridable per person.
    add_column :house_roles, :default_hourly_rate_cents, :integer
  end
end
