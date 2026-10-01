# frozen_string_literal: true

# CocoScout Ticketing: we sell the tickets ourselves. A listing puts one show on
# sale; tiers are its prices and seats; an order is one purchase (or a door
# sale, or comps) and its tickets are the admissions the door scans.
#
# Orders already say which way their money went (money_path) and which outside
# site sold them (ticket_channel_id / external_order_id, unused until the first
# integration), so selling the same show on Eventbrite later needs no schema
# change here. Seat counting lives in one place: Ticketing::Inventory.
class CreateTicketing < ActiveRecord::Migration[8.1]
  def change
    create_table :ticketing_profiles do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false # pilot flag, set by a superadmin
      t.string :slug, null: false
      t.string :support_email
      t.string :default_fee_mode, null: false, default: "buyer"
      t.integer :default_max_per_order, null: false, default: 10
      t.timestamps
    end
    add_index :ticketing_profiles, :slug, unique: true

    create_table :ticket_listings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true, index: { unique: true }
      t.references :production, null: false, foreign_key: true
      t.references :contract, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "draft"
      t.string :slug, null: false
      t.datetime :on_sale_at
      t.datetime :off_sale_at
      t.integer :capacity
      t.string :fee_mode
      t.integer :max_per_order
      t.string :title
      t.text :description
      t.string :door_note
      t.string :age_note
      t.string :accessibility_note
      t.datetime :released_at
      t.timestamps
    end
    add_index :ticket_listings, %i[organization_id slug], unique: true
    add_index :ticket_listings, %i[organization_id status]

    create_table :ticket_tiers do |t|
      t.references :ticket_listing, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.integer :price_cents, null: false, default: 0
      t.integer :quantity
      t.integer :position, null: false, default: 0
      t.datetime :sales_start_at
      t.datetime :sales_end_at
      t.boolean :hidden, null: false, default: false
      t.string :unlock_code
      t.integer :min_per_order, null: false, default: 1
      t.integer :max_per_order
      t.datetime :archived_at
      t.timestamps
    end

    create_table :ticket_discount_codes do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, foreign_key: true
      t.references :production, foreign_key: true
      t.string :code, null: false
      t.string :kind, null: false, default: "fixed"
      t.integer :amount_cents
      t.decimal :percent, precision: 5, scale: 2
      t.jsonb :ticket_tier_ids, null: false, default: []
      t.integer :max_uses
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ticket_discount_codes, %i[organization_id code]

    create_table :ticket_orders do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      t.string :code, null: false
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.string :channel, null: false, default: "online"
      t.string :money_path, null: false, default: "cocoscout"
      t.bigint :ticket_channel_id
      t.string :external_order_id
      t.string :buyer_name
      t.string :buyer_email
      t.string :buyer_phone
      t.boolean :marketing_opt_in, null: false, default: false
      t.string :fee_mode, null: false
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :platform_fee_cents, null: false, default: 0
      t.integer :processing_cents, null: false, default: 0
      t.integer :buyer_fee_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :org_net_cents, null: false, default: 0
      t.integer :refunded_cents, null: false, default: 0
      t.references :ticket_discount_code, foreign_key: { on_delete: :nullify }
      t.datetime :expires_at
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.integer :stripe_fee_cents
      t.datetime :paid_at
      t.datetime :canceled_at
      t.datetime :refunded_at
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :client_ip
      t.string :referrer
      t.jsonb :utm, null: false, default: {}
      t.timestamps
    end
    add_index :ticket_orders, :code, unique: true
    add_index :ticket_orders, :token, unique: true
    add_index :ticket_orders, :stripe_payment_intent_id, unique: true, where: "stripe_payment_intent_id IS NOT NULL"
    add_index :ticket_orders, %i[ticket_listing_id status]
    add_index :ticket_orders, %i[organization_id created_at]
    add_index :ticket_orders, :buyer_email
    add_index :ticket_orders, :expires_at, where: "status = 'pending'"

    create_table :tickets do |t|
      t.references :ticket_order, null: false, foreign_key: true
      t.references :ticket_tier, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true, index: false
      t.string :code, null: false
      t.string :external_barcode
      t.string :holder_name
      t.integer :price_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.string :status, null: false, default: "reserved"
      t.datetime :checked_in_at
      t.references :checked_in_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :refunded_at
      t.timestamps
    end
    add_index :tickets, :code, unique: true
    add_index :tickets, %i[ticket_listing_id status]
    add_index :tickets, %i[ticket_listing_id external_barcode], unique: true, where: "external_barcode IS NOT NULL"

    create_table :ticketing_access_grants do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :access_level, null: false, default: "check_in"
      t.references :granted_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ticketing_access_grants, %i[organization_id user_id], unique: true, where: "revoked_at IS NULL",
              name: "idx_ticketing_access_grants_one_active"

    # The built-in "CocoScout Tickets" source: its Show Financials rows fill
    # themselves from ticket sales.
    add_column :ticket_sources, :system_key, :string
    add_index :ticket_sources, %i[organization_id system_key], unique: true, where: "system_key IS NOT NULL"
  end
end
