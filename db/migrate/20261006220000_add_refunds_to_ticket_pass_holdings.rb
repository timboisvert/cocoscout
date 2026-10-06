# frozen_string_literal: true

# A credit pass nobody used yet can be refunded in full (TicketPassCredits.refund!).
class AddRefundsToTicketPassHoldings < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_pass_holdings, :refunded_cents, :integer, null: false, default: 0
    add_column :ticket_pass_holdings, :refund_org_debit_cents, :integer, null: false, default: 0
    add_column :ticket_pass_holdings, :stripe_refund_id, :string
    add_column :ticket_pass_holdings, :refunded_at, :datetime
    add_index :ticket_pass_holdings, :stripe_refund_id
  end
end
