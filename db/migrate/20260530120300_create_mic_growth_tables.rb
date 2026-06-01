# frozen_string_literal: true

# Block 3 of the Mics Finder build. Performer-facing growth tables:
# favorites + sign-up open alerts.
class CreateMicGrowthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :mic_favorites do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :user_id, null: false
      t.text :note
      t.timestamps
    end
    add_index :mic_favorites, %i[user_id mic_id], unique: true

    create_table :mic_signup_alerts do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :user_id, null: false
      t.jsonb :channels, null: false, default: [ "email" ]
      t.integer :lead_time_minutes, null: false, default: 5
      t.datetime :next_target_at
      t.datetime :last_delivered_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :mic_signup_alerts, %i[user_id mic_id], unique: true
    add_index :mic_signup_alerts, :next_target_at, where: "active = true"
  end
end
