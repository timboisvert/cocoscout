# frozen_string_literal: true

# Passes used later (Tim, 2026-10-05): a punch card (N admissions, any mix) or
# a season pass (one seat a show, up to N shows), covering productions, until
# an end date. Each one bought is a holding with credits; using a credit
# makes that show's tickets. Unused credits are the organization's when the
# pass ends.
class CreateTicketPassHoldings < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_passes, :credits, :integer
    add_column :ticket_passes, :ends_on, :date

    create_table :ticket_pass_coverages do |t|
      t.references :ticket_pass, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      # Which ticket type a credit gives at each date; blank, its first.
      t.string :tier_name
      t.timestamps
    end
    add_index :ticket_pass_coverages, %i[ticket_pass_id production_id], unique: true

    create_table :ticket_pass_holdings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_pass, null: false, foreign_key: true
      t.references :ticket_purchase, foreign_key: true
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.integer :credits, null: false
      # What one credit counts at the show it's used on: price ÷ credits.
      t.integer :credit_value_cents, null: false, default: 0
      t.date :ends_on, null: false
      t.string :holder_name
      t.string :holder_email
      t.integer :price_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :platform_fee_cents, null: false, default: 0
      t.integer :processing_cents, null: false, default: 0
      t.integer :buyer_fee_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :org_net_cents, null: false, default: 0
      # What Stripe took to process a purchase of passes alone (no ticket
      # order to carry it), on its first holding.
      t.integer :stripe_fee_cents
      t.datetime :paid_at
      t.datetime :ended_at
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :ticket_pass_holdings, :token, unique: true

    add_reference :tickets, :ticket_pass_holding, foreign_key: true
  end
end
