# frozen_string_literal: true

# Products sold with tickets (a bottle of champagne for the table): defined
# once per organization, upsold per production, bought at checkout as lines
# on the order, handed over at the door.
class CreateTicketProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_products do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.integer :price_cents, null: false, default: 0
      # Does a sale of it count as ticket revenue (what a contract's revenue
      # share is computed on)? Off unless the theater says so.
      t.boolean :counts_toward_ticket_revenue, null: false, default: false
      # The ticket tax applies to it.
      t.boolean :taxable, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end

    # Which products a production upsells, in order, with its own price and
    # revenue rule when production_ticketings.own_product_prices is on.
    create_table :production_ticketing_products do |t|
      t.references :production_ticketing, null: false, foreign_key: true
      t.references :ticket_product, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :price_cents
      t.boolean :counts_toward_ticket_revenue
      t.timestamps
      t.index %i[production_ticketing_id ticket_product_id], unique: true, name: "idx_production_ticketing_products_unique"
    end
    add_column :production_ticketings, :own_product_prices, :boolean, null: false, default: false

    # One product line on an order: what was bought, at what price, and
    # whether it's been handed over.
    create_table :ticket_order_items do |t|
      t.references :ticket_order, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_product, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.integer :unit_price_cents, null: false, default: 0
      t.integer :quantity, null: false, default: 1
      t.integer :tax_cents, null: false, default: 0
      t.boolean :counts_toward_ticket_revenue, null: false, default: false
      t.string :status, null: false, default: "reserved"
      t.integer :fulfilled_quantity, null: false, default: 0
      t.datetime :fulfilled_at
      t.references :fulfilled_by, foreign_key: { to_table: :users }
      t.datetime :refunded_at
      t.timestamps
      t.index %i[ticket_listing_id status]
    end

    add_column :ticket_refunds, :item_ids, :jsonb, null: false, default: []
    add_column :ticket_refunds, :product_cents, :integer, null: false, default: 0
  end
end
