# frozen_string_literal: true

# Pro billed on the one monthly bill (Tim, 2026-11-01): from pro_monthly_from
# the organization is on Pro, and each month's bill carries the plan for that
# month beside its usage, instead of a second Stripe subscription sending a
# second bill. pro_monthly_until ends it (the end of the month it was canceled).
class AddProMonthlyToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :pro_monthly_from, :datetime
    add_column :organizations, :pro_monthly_until, :datetime
  end
end
