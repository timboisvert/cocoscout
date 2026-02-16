# frozen_string_literal: true

class CreateProductionTicketingSetup < ActiveRecord::Migration[8.0]
  def change
    # Production Ticketing Setup - wizard-created configuration that defines
    # how a production's shows should be listed on ticketing providers
    create_table :production_ticketing_setups do |t|
      t.references :production, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true

      # Listing strategy
      t.string :listing_mode, null: false, default: "all_shows"
      # all_shows: All shows (past and future) get listed
      # future_only: Only shows from setup date forward
      # selected_shows: Manually specify which shows (via rules)

      t.string :grouping_strategy, null: false, default: "individual_events"
      # individual_events: Each show is its own event on the provider
      # recurring_event: All shows appear as occurrences/dates of one event (provider-permitting)

      # Event information defaults (can be overridden per-show)
      t.string :title_template # e.g., "{production_name} - {show_date}" or just "{production_name}"
      t.text :description
      t.text :short_description

      # Venue info (defaults from production/shows but can be overridden)
      t.string :default_venue_name
      t.text :default_venue_address
      t.string :default_venue_city
      t.string :default_venue_postal_code
      t.string :default_venue_country, default: "US"
      t.boolean :online_event, default: false

      # Default pricing template (stored as JSON array of tier configs)
      # Each tier: {name:, price_cents:, description:, quantity_per_show:}
      t.jsonb :default_pricing_tiers, default: []

      # Provider-uploaded images stored via Active Storage (see model)

      # Timezone for event times
      t.string :timezone, default: "America/New_York"

      # Currency for pricing
      t.string :currency, default: "USD"

      # Status
      t.string :status, null: false, default: "draft"
      # draft: Still being configured
      # active: Actively syncing to providers
      # paused: Temporarily stopped syncing (keeps remote events)
      # archived: No longer active, historical only

      t.datetime :activated_at # When status changed to active
      t.datetime :paused_at
      t.datetime :archived_at

      # Audit
      t.references :created_by, foreign_key: { to_table: :people }
      t.datetime :wizard_completed_at

      t.timestamps
    end

    # Provider-specific configurations for this setup
    create_table :ticketing_provider_setups do |t|
      t.references :production_ticketing_setup, null: false, foreign_key: true, index: { name: "idx_provider_setups_on_setup" }
      t.references :ticketing_provider, null: false, foreign_key: true

      t.boolean :enabled, default: true

      # Provider-specific overrides (optional)
      t.string :custom_title # Override title for this provider
      t.text :custom_description # Override description for this provider

      # Provider-specific settings (varies by provider)
      t.jsonb :provider_settings, default: {}
      # Eventbrite: {category_id:, format_id:, organizer_id:, listed: true/false}
      # Ticket Tailor: {access_code:, waitlist_active:, box_office_slug:}

      # Cache of remote IDs for "recurring_event" mode where one event has multiple dates
      t.string :remote_event_series_id # The parent event/series ID on the provider
      t.string :remote_event_series_url

      t.timestamps
    end

    add_index :ticketing_provider_setups, [ :production_ticketing_setup_id, :ticketing_provider_id ],
              unique: true, name: "idx_provider_setups_unique"

    # Per-show rules: exclusions, overrides, or explicit inclusions
    create_table :show_ticketing_rules do |t|
      t.references :production_ticketing_setup, null: false, foreign_key: true, index: { name: "idx_show_rules_on_setup" }
      t.references :show, null: false, foreign_key: true

      t.string :rule_type, null: false
      # exclude: Don't list this show (removes from providers if already listed)
      # include: Explicitly include (used when listing_mode is "selected_shows")
      # override: Use different settings for this show

      # Override data (only for rule_type = "override")
      t.jsonb :override_data, default: {}
      # Can include: {title:, description:, pricing_tiers:[], provider_ids:[]}
      # provider_ids: If set, only list on these specific providers (subset)

      # User-facing reason for exclusion/override
      t.string :reason

      # Which providers this rule applies to (null = all)
      # For fine-grained control: "Don't list this show on Eventbrite but do on Ticket Tailor"
      t.jsonb :applies_to_provider_ids

      t.timestamps
    end

    add_index :show_ticketing_rules, [ :production_ticketing_setup_id, :show_id ],
              unique: true, name: "idx_show_rules_unique"

    # Remote Ticketing Events - cache of what actually exists on provider sites
    # This is NOT intent - it's a record of what we've successfully created/synced
    create_table :remote_ticketing_events do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :production_ticketing_setup, foreign_key: true, index: { name: "idx_remote_events_on_setup" }
      t.references :show, foreign_key: true # Null for grouped "parent" events
      t.references :organization, null: false, foreign_key: true

      # External identifiers
      t.string :external_event_id, null: false
      t.string :external_occurrence_id # For providers that have event + occurrence
      t.string :external_url

      # Remote status (what the provider says)
      t.string :remote_status
      # draft, live, published, sales_closed, canceled, sold_out, etc.

      # Cached metrics (pulled from provider)
      t.integer :tickets_sold, default: 0
      t.integer :tickets_available, default: 0
      t.integer :capacity, default: 0
      t.integer :revenue_cents, default: 0
      t.string :revenue_currency, default: "USD"

      # Last time we fetched data from the provider
      t.datetime :last_synced_at
      t.datetime :last_sales_synced_at

      # Raw data from provider (for debugging/reference)
      t.jsonb :raw_data, default: {}

      # Sync status
      t.string :sync_status, default: "synced"
      # synced: Matches our rules
      # pending_update: We need to push changes
      # pending_delete: We need to remove this
      # orphaned: Exists on provider but shouldn't (setup deleted, show excluded, etc.)

      t.text :last_sync_error

      t.timestamps
    end

    add_index :remote_ticketing_events, [ :ticketing_provider_id, :external_event_id ],
              unique: true, name: "idx_remote_events_provider_external"
    add_index :remote_ticketing_events, [ :ticketing_provider_id, :show_id ],
              name: "idx_remote_events_provider_show"
  end
end
