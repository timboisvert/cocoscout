class CreateProviderEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_events do |t|
      t.references :ticketing_provider, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :external_event_id, null: false
      t.string :external_series_id
      t.string :name
      t.text :description
      t.string :venue_name
      t.string :status, default: "active"
      t.references :production, null: true, foreign_key: true
      t.string :match_status, default: "unmatched"
      t.decimal :match_confidence, precision: 5, scale: 3
      t.datetime :last_synced_at
      t.jsonb :raw_data, default: {}

      t.timestamps
    end
    add_index :provider_events, [ :ticketing_provider_id, :external_event_id ], unique: true, name: "idx_provider_events_unique"
  end
end
