class CreateTicketingShowLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :ticketing_show_links do |t|
      t.references :show, null: false, foreign_key: true
      t.references :ticketing_production_link, null: false, foreign_key: true

      # External identifiers
      t.string :provider_occurrence_id
      t.string :provider_ticket_page_url

      # Cached ticket data (updated on sync)
      t.integer :tickets_sold, default: 0
      t.integer :tickets_available
      t.integer :tickets_capacity
      t.decimal :gross_revenue, precision: 10, scale: 2
      t.decimal :net_revenue, precision: 10, scale: 2
      t.jsonb :ticket_breakdown, default: []

      # Status
      t.datetime :provider_updated_at
      t.datetime :last_synced_at
      t.string :last_sync_hash
      t.string :sync_status
      t.text :sync_notes

      t.timestamps
    end

    add_index :ticketing_show_links, :provider_occurrence_id
    add_index :ticketing_show_links,
              %i[show_id ticketing_production_link_id],
              unique: true,
              name: "idx_ticketing_show_links_unique"
  end
end
