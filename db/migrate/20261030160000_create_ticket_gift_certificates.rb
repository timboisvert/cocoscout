# frozen_string_literal: true

# Gift certificates, barebones (Tim, 2026-10-30): a manager issues one with a
# dollar value; a buyer types its code on the checkout page and it pays for
# the order instead of (or before) a card. Web checkout only for now.
class CreateTicketGiftCertificates < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_gift_certificates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :code, null: false
      t.integer :amount_cents, null: false
      # What's left to spend; each checkout draws it down.
      t.integer :remaining_cents, null: false
      t.string :recipient_name
      t.string :recipient_email
      t.string :note
      # any: every show the organization sells; some: the scopes below.
      t.string :scope, null: false, default: "any"
      t.references :issued_by, foreign_key: { to_table: :users }
      t.datetime :voided_at
      t.references :voided_by, foreign_key: { to_table: :users }
      t.datetime :emailed_at
      t.timestamps
    end
    add_index :ticket_gift_certificates, :code, unique: true

    # What a "some" certificate is good for: a production (every date of it),
    # or one of its dates.
    create_table :ticket_gift_certificate_scopes do |t|
      t.references :ticket_gift_certificate, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.references :ticket_listing, foreign_key: true
      t.timestamps
    end

    # Money drawn from a certificate: held by a checkout, then redeemed when
    # it's paid (or released when the hold runs out); a refund puts money
    # back with a row of its own.
    create_table :ticket_gift_certificate_redemptions do |t|
      t.references :ticket_gift_certificate, null: false, foreign_key: true
      t.references :ticket_purchase, foreign_key: true
      t.references :ticket_order, foreign_key: true
      t.references :ticket_refund, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "held"
      t.timestamps
    end

    # What a certificate paid of each order and checkout (the card paid the rest).
    add_reference :ticket_orders, :ticket_gift_certificate, foreign_key: true
    add_column :ticket_orders, :gift_certificate_cents, :integer, null: false, default: 0
    add_reference :ticket_purchases, :ticket_gift_certificate, foreign_key: true
    add_column :ticket_purchases, :gift_certificate_cents, :integer, null: false, default: 0
    # The part of a refund that went back onto the certificate, not a card.
    add_column :ticket_refunds, :gift_certificate_cents, :integer, null: false, default: 0
  end
end
