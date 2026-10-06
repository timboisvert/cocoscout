# frozen_string_literal: true

# When CocoScout emailed a bill, and its receipt, so each goes once.
class AddEmailTimesToBillingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_invoices, :bill_emailed_at, :datetime
    add_column :billing_invoices, :receipt_emailed_at, :datetime
  end
end
