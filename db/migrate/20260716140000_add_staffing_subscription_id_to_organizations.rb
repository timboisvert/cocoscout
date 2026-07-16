# frozen_string_literal: true

# The org's separate, always-monthly Stripe subscription that carries the two
# metered staffing prices ($5/active staff, $1/extra payment). It's decoupled
# from the Pro base plan (which may be annual) so staffing usage bills the same
# way regardless of the Pro billing interval. Created lazily the first time an
# org meters staffing (see StaffMeterService).
class AddStaffingSubscriptionIdToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :staffing_subscription_id, :string
    add_index :organizations, :staffing_subscription_id
  end
end
