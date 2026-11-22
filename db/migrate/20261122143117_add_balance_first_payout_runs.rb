# frozen_string_literal: true

# Payout runs pay as many people as they can from the organization's
# CocoScout balance the moment they're submitted, in pay order, and the rest
# as the balance grows, with the bank paying whoever is left on a deadline
# (Tim, 2026-11-22).
#
#   organizations.payout_pay_order         the default order: groups of payees
#   organizations.payout_waits_on_balance  the rest wait on the balance, paid
#                                          each morning as it clears (off: the
#                                          bank pays them when the run is submitted)
#   organizations.payout_bank_after_days   days the rest wait on the balance
#                                          before the bank pays them
#   payout_batches.pay_order               this run's own order, when changed
#                                          ({ "groups" => [...], "payees" => [...] })
#   payout_batches.bank_due_at             when the bank pays this run's rest
#   payout_batch_items.paid_from_balance   paid from the balance, not from the
#                                          run's bank debit
class AddBalanceFirstPayoutRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :payout_pay_order, :jsonb, default: %w[staffing contractor performer], null: false
    add_column :organizations, :payout_waits_on_balance, :boolean, default: true, null: false
    add_column :organizations, :payout_bank_after_days, :integer, default: 3, null: false
    add_column :payout_batches, :pay_order, :jsonb, default: {}, null: false
    add_column :payout_batches, :bank_due_at, :datetime
    add_column :payout_batch_items, :paid_from_balance, :boolean, default: false, null: false
  end
end
