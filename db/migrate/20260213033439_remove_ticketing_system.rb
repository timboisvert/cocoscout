class RemoveTicketingSystem < ActiveRecord::Migration[8.1]
  def up
    # Remove ticket_fees column from show_financials (keep ticket_count, ticket_revenue, revenue_type)
    remove_column :show_financials, :ticket_fees, :jsonb if column_exists?(:show_financials, :ticket_fees)

    # Drop ticketing tables in correct order (respecting foreign keys)
    drop_table :ticketing_sync_logs if table_exists?(:ticketing_sync_logs)
    drop_table :ticketing_show_links if table_exists?(:ticketing_show_links)
    drop_table :ticketing_pending_events if table_exists?(:ticketing_pending_events)
    drop_table :ticketing_production_links if table_exists?(:ticketing_production_links)
    drop_table :ticketing_providers if table_exists?(:ticketing_providers)
    drop_table :ticket_fee_templates if table_exists?(:ticket_fee_templates)
  end

  def down
    # Recreate ticket_fee_templates
    create_table :ticket_fee_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.decimal :flat_per_ticket, precision: 10, scale: 4, default: "0.0"
      t.decimal :percentage, precision: 5, scale: 2, default: "0.0"
      t.string :name, null: false
      t.boolean :is_default, default: false
      t.timestamps
    end
    add_index :ticket_fee_templates, [:organization_id, :name], unique: true

    # Recreate ticketing_providers
    create_table :ticketing_providers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :name, null: false
      t.text :encrypted_credentials
      t.boolean :auto_sync_enabled, default: true
      t.integer :sync_interval_minutes, default: 60
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.timestamps
    end

    # Recreate ticketing_production_links
    create_table :ticketing_production_links do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.string :provider_event_id, null: false
      t.string :provider_event_name
      t.boolean :sync_ticket_sales, default: true
      t.jsonb :ticket_type_mappings, default: {}
      t.timestamps
    end
    add_index :ticketing_production_links, [:ticketing_provider_id, :provider_event_id], unique: true, name: "idx_ticketing_prod_links_provider_event"

    # Recreate ticketing_show_links
    create_table :ticketing_show_links do |t|
      t.references :show, null: false, foreign_key: true
      t.references :ticketing_production_link, null: false, foreign_key: true
      t.string :provider_occurrence_id, null: false
      t.string :provider_ticket_page_url
      t.integer :tickets_sold, default: 0
      t.integer :tickets_available
      t.integer :tickets_capacity
      t.decimal :gross_revenue, precision: 10, scale: 2, default: 0
      t.jsonb :fee_breakdown, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :ticketing_show_links, [:ticketing_production_link_id, :provider_occurrence_id], unique: true, name: "idx_ticketing_show_links_link_occurrence"

    # Recreate ticketing_pending_events
    create_table :ticketing_pending_events do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.string :provider_event_id, null: false
      t.string :provider_event_name
      t.jsonb :event_data, default: {}
      t.string :status, default: "pending"
      t.references :suggested_production, foreign_key: { to_table: :productions }
      t.references :matched_production_link, foreign_key: { to_table: :ticketing_production_links }
      t.references :dismissed_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :ticketing_pending_events, [:ticketing_provider_id, :provider_event_id], unique: true, name: "idx_pending_events_provider_event"
    add_index :ticketing_pending_events, :status

    # Recreate ticketing_sync_logs
    create_table :ticketing_sync_logs do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :ticketing_production_link, foreign_key: true
      t.references :triggered_by, foreign_key: { to_table: :users }
      t.string :sync_type, null: false
      t.string :status, default: "running"
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_failed, default: 0
      t.text :error_message
      t.jsonb :details, default: {}
      t.timestamps
    end
    add_index :ticketing_sync_logs, [:ticketing_provider_id, :created_at], name: "idx_ticketing_sync_logs_provider_created"
    add_index :ticketing_sync_logs, :status

    # Re-add ticket_fees column to show_financials
    add_column :show_financials, :ticket_fees, :jsonb, default: []
  end
end
