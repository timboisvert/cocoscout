# frozen_string_literal: true

# Who gets CocoScout's bills, receipts and monthly statements: the managers
# ticked on the Billing & Plan tab plus any other addresses typed there.
# Nobody chosen means the owner, as before (Tim, 2026-10-06). The three
# templates are re-seeded so their first_name variable stops saying "owner".
class AddBillingContactsToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :billing_contact_user_ids, :jsonb, default: [], null: false
    add_column :organizations, :billing_contact_emails, :jsonb, default: [], null: false
    PlatformTemplates.ensure!(keys: %w[org_monthly_statement cocoscout_bill cocoscout_bill_paid], overwrite: true)
  end

  def down
    remove_column :organizations, :billing_contact_user_ids
    remove_column :organizations, :billing_contact_emails
  end
end
