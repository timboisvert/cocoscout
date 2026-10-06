# frozen_string_literal: true

# A pass: tickets to several shows sold as one thing ("Twilight Double
# Feature: both nights for $30"). A dated pass names its shows and the ticket
# type at each; buying one takes a seat at every show. Kinds for passes used
# later (punch cards, season passes) come next.
class CreateTicketPasses < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_passes do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :kind, null: false, default: "dated"
      t.integer :price_cents, null: false, default: 0
      # How the price lands on each show: regular_price, even, or custom.
      t.string :split, null: false, default: "regular_price"
      t.string :status, null: false, default: "draft"
      t.datetime :sales_start_at
      t.datetime :sales_end_at
      t.integer :max_sold
      t.integer :max_per_order
      t.timestamps
    end
    add_index :ticket_passes, %i[organization_id slug], unique: true

    create_table :ticket_pass_shows do |t|
      t.references :ticket_pass, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :ticket_tier, null: false, foreign_key: true
      t.integer :share_cents
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ticket_pass_shows, %i[ticket_pass_id ticket_listing_id], unique: true

    add_reference :tickets, :ticket_pass, foreign_key: true
  end
end
