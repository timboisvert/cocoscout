# frozen_string_literal: true

# Webhooks a handler failed on get retried instead of dropped, a run's bank
# debit can't be made twice, and a comp can cover the usage charges
# separately from the plan.
class MoneySafety < ActiveRecord::Migration[8.1]
  def up
    add_column :webhook_events, :status, :string, null: false, default: "processing"
    add_column :webhook_events, :attempts, :integer, null: false, default: 1
    add_column :webhook_events, :error, :text
    add_column :webhook_events, :processed_at, :datetime
    add_column :webhook_events, :updated_at, :datetime
    execute "UPDATE webhook_events SET status = 'processed', processed_at = created_at, updated_at = created_at"
    add_index :webhook_events, :status, where: "status <> 'processed'"

    # Each funding attempt gets its own Stripe idempotency key.
    add_column :payout_batches, :funding_attempts, :integer, null: false, default: 0
    # Funding credit a run spent, so a debit that bounces days later gives it back.
    add_column :payout_batches, :credit_applied_cents, :bigint, null: false, default: 0

    # A withdrawal is followed to the theater's bank: Stripe's payout from
    # their account says when it landed, or that their bank turned it down.
    add_column :balance_withdrawals, :stripe_payout_id, :string
    add_column :balance_withdrawals, :paid_at, :datetime
    add_index :balance_withdrawals, :stripe_transfer_id

    add_column :organizations, :comped_usage, :boolean, null: false, default: false
    # Nobody comped today gets a surprise usage bill: usage starts comped too.
    execute "UPDATE organizations SET comped_usage = TRUE WHERE comped_indefinitely OR comped_until > NOW()"
  end

  def down
    remove_index :webhook_events, :status
    remove_column :webhook_events, :status
    remove_column :webhook_events, :attempts
    remove_column :webhook_events, :error
    remove_column :webhook_events, :processed_at
    remove_column :webhook_events, :updated_at
    remove_column :payout_batches, :funding_attempts
    remove_column :payout_batches, :credit_applied_cents
    remove_index :balance_withdrawals, :stripe_transfer_id
    remove_column :balance_withdrawals, :stripe_payout_id
    remove_column :balance_withdrawals, :paid_at
    remove_column :organizations, :comped_usage
  end
end
