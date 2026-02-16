class FixTicketSyncRulesTable < ActiveRecord::Migration[8.1]
  def change
    # Recreate ticket_sync_rules with the correct schema
    # Drop the old table and create the correct one
    drop_table :ticket_sync_rules, if_exists: true

    create_table :ticket_sync_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticketing_provider, null: false, foreign_key: true
      t.string :name, null: false
      t.string :rule_type, null: false, default: "sync_all" # sync_all, sync_production, sync_venue
      t.integer :sync_interval_minutes, null: false, default: 15
      t.boolean :active, null: false, default: true
      t.datetime :next_sync_at
      t.jsonb :rule_config, default: {} # Rule parameters (production_id, location_id, etc.)
      t.timestamps

      t.index [ :organization_id, :active ]
      t.index [ :ticketing_provider_id, :active ]
      t.index [ :next_sync_at, :active ]
    end
  end
end
