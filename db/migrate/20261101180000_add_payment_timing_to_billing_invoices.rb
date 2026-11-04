# frozen_string_literal: true

# How and when each bill gets paid, mirrored from Stripe: whether it charges
# automatically or waits on the organization to pay it, when Stripe next
# tries, its due date, and the payment in flight (a bank debit takes about
# four business days, and Stripe's balance only shows it once it lands).
# And what's been given back on it: refunds and credits on its credit notes,
# credits put on the customer's balance while it was still being collected,
# and credit from the customer's balance the bill used up.
class AddPaymentTimingToBillingInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :billing_invoices, :collection_method, :string
    add_column :billing_invoices, :due_at, :datetime
    add_column :billing_invoices, :next_payment_attempt_at, :datetime
    add_column :billing_invoices, :payment_status, :string
    add_column :billing_invoices, :payment_method_type, :string
    add_column :billing_invoices, :payment_started_at, :datetime
    add_column :billing_invoices, :credit_notes_cents, :bigint, default: 0, null: false
    add_column :billing_invoices, :balance_credited_cents, :bigint, default: 0, null: false
    add_column :billing_invoices, :balance_applied_cents, :bigint, default: 0, null: false
  end
end
