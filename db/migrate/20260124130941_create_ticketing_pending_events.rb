class CreateTicketingPendingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ticketing_pending_events do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.string :provider_event_id, null: false
      t.string :provider_event_name
      t.jsonb :provider_event_data, default: {}
      t.integer :occurrence_count, default: 0
      t.datetime :first_occurrence_at
      t.datetime :last_occurrence_at
      t.string :status, default: "pending", null: false
      t.references :suggested_production, foreign_key: { to_table: :productions }
      t.float :match_confidence
      t.references :matched_production_link, foreign_key: { to_table: :ticketing_production_links }
      t.datetime :dismissed_at
      t.references :dismissed_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :ticketing_pending_events, [:ticketing_provider_id, :provider_event_id],
              unique: true, name: "idx_pending_events_provider_event"
    add_index :ticketing_pending_events, :status
  end
end
