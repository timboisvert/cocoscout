# frozen_string_literal: true

class DropTicketingAndSeatingTables < ActiveRecord::Migration[8.0]
  def up
    # Drop foreign keys first to avoid dependency issues.
    # We use safe_remove_foreign_key style with rescue so the migration is
    # idempotent across environments that may already be partially cleaned up.
    drop_fk_if_exists("ticketing_provider_setups", "production_ticketing_setups")
    drop_fk_if_exists("ticketing_provider_setups", "ticketing_providers")
    drop_fk_if_exists("ticketing_providers", "organizations")
    drop_fk_if_exists("ticketing_activities", "productions")
    drop_fk_if_exists("ticketing_activities", "shows")
    drop_fk_if_exists("ticket_tiers", "seating_configurations")
    drop_fk_if_exists("ticket_tiers", "seating_zones")
    drop_fk_if_exists("ticket_sync_rules", "organizations")
    drop_fk_if_exists("ticket_sync_rules", "ticketing_providers")
    drop_fk_if_exists("ticket_sales", "show_ticket_tiers")
    drop_fk_if_exists("ticket_sales", "ticket_offers")
    drop_fk_if_exists("ticket_offers", "show_ticket_tiers")
    drop_fk_if_exists("ticket_offers", "ticket_listings")
    drop_fk_if_exists("ticket_listings", "show_ticketings")
    drop_fk_if_exists("ticket_listings", "ticketing_providers")
    drop_fk_if_exists("ticket_bundles", "show_ticketings")
    drop_fk_if_exists("ticket_bundle_items", "show_ticket_tiers")
    drop_fk_if_exists("ticket_bundle_items", "ticket_bundles")
    drop_fk_if_exists("show_ticketings", "seating_configurations")
    drop_fk_if_exists("show_ticketings", "shows")
    drop_fk_if_exists("show_ticketing_rules", "production_ticketing_setups")
    drop_fk_if_exists("show_ticketing_rules", "shows")
    drop_fk_if_exists("show_ticket_tiers", "show_ticketings")
    drop_fk_if_exists("show_ticket_tiers", "ticket_tiers")
    drop_fk_if_exists("seating_zones", "seating_configurations")
    drop_fk_if_exists("seating_configurations", "location_spaces")
    drop_fk_if_exists("seating_configurations", "locations")
    drop_fk_if_exists("seating_configurations", "organizations")
    drop_fk_if_exists("remote_ticketing_events", "organizations")
    drop_fk_if_exists("remote_ticketing_events", "production_ticketing_setups")
    drop_fk_if_exists("remote_ticketing_events", "provider_events")
    drop_fk_if_exists("remote_ticketing_events", "shows")
    drop_fk_if_exists("remote_ticketing_events", "shows", column: "suggested_show_id")
    drop_fk_if_exists("remote_ticketing_events", "ticketing_providers")
    drop_fk_if_exists("provider_events", "organizations")
    drop_fk_if_exists("provider_events", "productions")
    drop_fk_if_exists("provider_events", "ticketing_providers")
    drop_fk_if_exists("production_ticketing_setups", "locations", column: "default_location_id")
    drop_fk_if_exists("production_ticketing_setups", "organizations")
    drop_fk_if_exists("production_ticketing_setups", "people", column: "created_by_id")
    drop_fk_if_exists("production_ticketing_setups", "productions")
    drop_fk_if_exists("production_ticketing_setups", "seating_configurations")
    drop_fk_if_exists("webhook_logs", "ticket_listings")
    drop_fk_if_exists("webhook_logs", "ticketing_providers")

    # Drop tables (order: leaves of the dependency tree first)
    drop_table_if_exists :ticket_sales
    drop_table_if_exists :ticket_offers
    drop_table_if_exists :ticket_bundle_items
    drop_table_if_exists :ticket_bundles
    drop_table_if_exists :webhook_logs
    drop_table_if_exists :ticket_listings
    drop_table_if_exists :ticket_sync_rules
    drop_table_if_exists :ticketing_activities
    drop_table_if_exists :ticketing_provider_setups
    drop_table_if_exists :show_ticket_tiers
    drop_table_if_exists :show_ticketing_rules
    drop_table_if_exists :show_ticketings
    drop_table_if_exists :ticket_tiers
    drop_table_if_exists :seating_zones
    drop_table_if_exists :remote_ticketing_events
    drop_table_if_exists :provider_events
    drop_table_if_exists :production_ticketing_setups
    drop_table_if_exists :seating_configurations
    drop_table_if_exists :ticketing_providers

    # Remove ticketing columns left on productions / shows
    if column_exists?(:productions, :ticketing_enabled)
      remove_column :productions, :ticketing_enabled
    end
    if column_exists?(:productions, :ticketing_exclusion_reason)
      remove_column :productions, :ticketing_exclusion_reason
    end
    if column_exists?(:shows, :ticketing_enabled)
      remove_column :shows, :ticketing_enabled
    end
    if column_exists?(:shows, :ticketing_exclusion_reason)
      remove_column :shows, :ticketing_exclusion_reason
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Ticketing system has been retired."
  end

  private

  def drop_fk_if_exists(from_table, to_table, **options)
    return unless table_exists?(from_table)
    return unless foreign_key_exists?(from_table, to_table, **options)
    remove_foreign_key(from_table, to_table, **options)
  rescue ActiveRecord::StatementInvalid
    # Already gone — safe to ignore
  end

  def drop_table_if_exists(name)
    drop_table(name) if table_exists?(name)
  end
end
