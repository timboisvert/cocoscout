class CreateTicketingActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :ticketing_activities do |t|
      t.references :production, null: false, foreign_key: true
      t.references :show, null: true, foreign_key: true  # Nullable - some activities are production-level
      t.string :event_type, null: false
      t.text :message, null: false
      t.jsonb :data, default: {}

      t.timestamps
    end

    # Index for efficiently fetching recent activities for a production
    add_index :ticketing_activities, [ :production_id, :created_at ], order: { created_at: :desc }
  end
end
