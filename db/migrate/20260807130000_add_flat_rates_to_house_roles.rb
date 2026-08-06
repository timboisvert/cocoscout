# frozen_string_literal: true

# Some roles aren't paid by the hour. Security comes in for the night and gets
# $50 whether that's three hours or five. Until now every role was hourly and
# every amount was rate × hours.
#
# A role is one or the other. Hours are still logged for flat roles — the
# labour record and Role Call don't change — they just don't drive the money.
class AddFlatRatesToHouseRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :house_roles, :pay_type, :string, default: "hourly", null: false
    add_column :house_roles, :default_flat_rate_cents, :integer

    # Per-member override, mirroring the existing per-member hourly rate.
    add_column :staff_role_qualifications, :flat_rate_cents, :integer
  end
end
