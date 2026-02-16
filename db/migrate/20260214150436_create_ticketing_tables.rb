# frozen_string_literal: true

class CreateTicketingTables < ActiveRecord::Migration[8.1]
  def change
    # Ticketing Providers - external ticketing platform integrations
    create_table :ticketing_providers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :provider_type, null: false # eventbrite, ticket_tailor, etc.
      t.string :name, null: false # Display name for this integration
      t.text :encrypted_credentials # Encrypted API keys/secrets
      t.string :status, null: false, default: "active" # active, inactive
      t.datetime :last_synced_at
      t.jsonb :settings, default: {} # Provider-specific settings
      t.timestamps

      t.index [ :organization_id, :provider_type ]
      t.index [ :organization_id, :status ]
    end

    # Seating Configurations - define reusable room layouts with ticket tiers
    create_table :seating_configurations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :location_space, foreign_key: true # Optional link to physical space
      t.string :name, null: false # e.g., "Main Stage - Standard"
      t.text :description
      t.string :status, null: false, default: "active" # active, archived
      t.timestamps

      t.index [ :organization_id, :status ]
    end

    # Ticket Tiers - seat categories within a configuration
    create_table :ticket_tiers do |t|
      t.references :seating_configuration, null: false, foreign_key: true
      t.string :name, null: false # e.g., "GA", "VIP Front-row"
      t.integer :capacity, null: false # Number of seats/spots
      t.integer :default_price_cents, default: 0
      t.integer :position, null: false, default: 0 # Ordering
      t.text :description
      t.timestamps

      t.index [ :seating_configuration_id, :position ]
    end

    # Show Ticketing - links a show to the ticketing system
    create_table :show_ticketings do |t|
      t.references :show, null: false, foreign_key: true, index: { unique: true, name: "idx_show_ticketings_show" }
      t.references :seating_configuration, foreign_key: true # Can be null if custom
      t.string :status, null: false, default: "draft" # draft, active, closed
      t.datetime :doors_open_at
      t.jsonb :inventory_snapshot, default: {} # Current state per tier
      t.jsonb :settings, default: {} # Show-specific ticketing settings
      t.timestamps

      t.index :status, name: "idx_show_ticketings_status"
    end

    # Show Ticket Tiers - per-show tier configuration (copies from seating config or custom)
    create_table :show_ticket_tiers do |t|
      t.references :show_ticketing, null: false, foreign_key: true
      t.references :ticket_tier, foreign_key: true # Link to template tier, if any
      t.string :name, null: false
      t.integer :capacity, null: false
      t.integer :available, null: false # Current availability
      t.integer :sold, null: false, default: 0
      t.integer :held, null: false, default: 0 # Reserved but not sold
      t.integer :default_price_cents, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index [ :show_ticketing_id, :position ]
    end

    # Ticket Listings - a listing on an external platform
    create_table :ticket_listings do |t|
      t.references :show_ticketing, null: false, foreign_key: true
      t.references :ticketing_provider, null: false, foreign_key: true
      t.string :external_event_id # ID on the external platform
      t.string :external_url # Link to the event
      t.string :status, null: false, default: "draft" # draft, published, paused, ended
      t.datetime :last_synced_at
      t.datetime :published_at
      t.jsonb :listing_data, default: {} # Platform-specific config
      t.jsonb :sync_errors, default: [] # Recent sync errors
      t.timestamps

      t.index [ :show_ticketing_id, :ticketing_provider_id ], unique: true
      t.index [ :ticketing_provider_id, :external_event_id ]
      t.index :status
    end

    # Ticket Offers - specific ticket types on a listing
    create_table :ticket_offers do |t|
      t.references :ticket_listing, null: false, foreign_key: true
      t.references :show_ticket_tier, null: false, foreign_key: true
      t.string :external_offer_id # ID on the external platform
      t.string :name, null: false # e.g., "1 GA Seat", "2 GA Seats Bundle"
      t.integer :quantity, null: false # How many of this offer available
      t.integer :sold, null: false, default: 0
      t.integer :seats_per_offer, null: false, default: 1 # Seats per purchase
      t.integer :price_cents, null: false
      t.string :status, null: false, default: "active" # active, paused, sold_out, hidden
      t.jsonb :offer_data, default: {} # Platform-specific metadata
      t.timestamps

      t.index [ :ticket_listing_id, :status ]
      t.index [ :ticket_listing_id, :external_offer_id ]
    end

    # Ticket Sales - record of each sale from any provider
    create_table :ticket_sales do |t|
      t.references :ticket_offer, null: false, foreign_key: true
      t.references :show_ticket_tier, null: false, foreign_key: true
      t.string :external_sale_id # ID from provider
      t.integer :quantity, null: false, default: 1 # Number of offers purchased
      t.integer :total_seats, null: false # Total seats (quantity * seats_per_offer)
      t.integer :total_cents, null: false # Total paid
      t.string :customer_name
      t.string :customer_email
      t.string :customer_phone
      t.datetime :purchased_at, null: false
      t.datetime :synced_at
      t.string :status, null: false, default: "confirmed" # confirmed, refunded, cancelled
      t.jsonb :sale_data, default: {} # Additional data from provider
      t.timestamps

      t.index [ :ticket_offer_id, :external_sale_id ], unique: true
      t.index [ :show_ticket_tier_id, :status ]
      t.index :purchased_at
      t.index :customer_email
    end

    # Ticket Sync Rules - rules for inventory synchronization
    create_table :ticket_sync_rules do |t|
      t.references :show_ticketing, null: false, foreign_key: true
      t.string :rule_type, null: false # disable_singles_at_low_inventory, etc.
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 0
      t.jsonb :config, default: {} # Rule parameters
      t.timestamps

      t.index [ :show_ticketing_id, :rule_type ]
      t.index [ :show_ticketing_id, :enabled, :priority ]
    end

    # Ticket Bundles - bundle definitions for an offer
    create_table :ticket_bundles do |t|
      t.references :show_ticketing, null: false, foreign_key: true
      t.string :name, null: false # e.g., "Date Night Special"
      t.text :description
      t.integer :discount_cents, default: 0 # Flat discount
      t.integer :discount_percent, default: 0 # Percentage discount
      t.boolean :enabled, null: false, default: true
      t.timestamps

      t.index [ :show_ticketing_id, :enabled ]
    end

    # Ticket Bundle Items - tiers included in a bundle
    create_table :ticket_bundle_items do |t|
      t.references :ticket_bundle, null: false, foreign_key: true
      t.references :show_ticket_tier, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1 # How many of this tier in the bundle
      t.timestamps

      t.index [ :ticket_bundle_id, :show_ticket_tier_id ], unique: true
    end
  end
end
