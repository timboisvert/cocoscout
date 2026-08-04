# frozen_string_literal: true

# Money an org already funded into its Stripe balance that a payout run no
# longer needs — e.g. a payee released from a funded run because they were paid
# another way (cash/Venmo). Rather than refunding (fees, reconciliation pain),
# the credit automatically reduces the ACH debit on the org's next run.
class CreatePayoutFundingCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_funding_credits do |t|
      t.references :organization, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.bigint :consumed_cents, null: false, default: 0
      t.string :note
      t.references :source, polymorphic: true
      t.timestamps
    end
  end
end
