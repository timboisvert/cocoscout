class CreateTicketingProductionLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_production_links do |t|
      t.references :production, null: false, foreign_key: true
      t.references :ticketing_provider, null: false, foreign_key: true

      # External identifiers
      t.string :provider_event_id, null: false
      t.string :provider_event_name
      t.string :provider_event_url

      # Sync settings
      t.boolean :sync_ticket_sales, default: true
      t.boolean :sync_enabled, default: true

      # Mapping configuration
      t.jsonb :field_mappings, default: {}
      t.jsonb :ticket_type_mappings, default: {}

      # Status
      t.datetime :last_synced_at
      t.string :last_sync_hash

      t.timestamps
    end

    add_index :ticketing_production_links,
              %i[production_id ticketing_provider_id],
              unique: true,
              name: "idx_ticketing_prod_links_unique"
    add_index :ticketing_production_links, :provider_event_id
  end
end
