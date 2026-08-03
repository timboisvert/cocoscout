# frozen_string_literal: true

# Some staff (e.g. salaried managers) are never paid through the Pay People
# grid except for the odd reimbursement. Orgs can exclude them in Staffing
# settings so they don't clog the grid — they stay revealable one-by-one from
# a "hidden people" list at the bottom for those rare one-off payments.
class AddExcludedFromPayToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_staff_members, :excluded_from_pay, :boolean, default: false, null: false
  end
end
