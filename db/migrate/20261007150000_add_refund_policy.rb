# frozen_string_literal: true

# A refund policy the box office declares (Tim, 2026-10-07): a window before
# the show (24 hours by default), no refunds, or case by case, and whether
# fees come back (not by default). A production can set its own (blank
# fields follow the box office). Each order keeps the policy it was sold
# under, and a refund made outside the policy says so.
class AddRefundPolicy < ActiveRecord::Migration[8.1]
  def change
    change_table :ticketing_profiles, bulk: true do |t|
      t.string :refund_policy, default: "window", null: false
      t.integer :refund_window_hours, default: 24, null: false
      t.boolean :refund_fees, default: false, null: false
      t.text :refund_policy_note
    end

    change_table :production_ticketings, bulk: true do |t|
      t.string :refund_policy
      t.integer :refund_window_hours
      t.boolean :refund_fees
      t.text :refund_policy_note
    end

    add_column :ticket_orders, :refund_policy, :jsonb

    change_table :ticket_refunds, bulk: true do |t|
      t.boolean :outside_policy, default: false, null: false
      t.string :policy_words
    end
  end
end
