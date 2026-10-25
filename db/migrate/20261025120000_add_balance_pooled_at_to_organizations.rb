# frozen_string_literal: true

# Once an organization's money pools into its CocoScout balance, it stays
# pooled: an organization that leaves Pro keeps one ledger, and a daily sweep
# (LapsedBalanceSweepJob) sends its balance to its bank, since it can no
# longer open the balance page. Stamped for everyone pooled today.
class AddBalancePooledAtToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :balance_pooled_at, :datetime
    Organization.reset_column_information

    Organization.find_each do |organization|
      pooled = organization.on_paid_plan? || TicketingProfile.find_by(organization_id: organization.id)&.enabled?
      organization.update_column(:balance_pooled_at, Time.current) if pooled
    end
  end

  def down
    remove_column :organizations, :balance_pooled_at
  end
end
