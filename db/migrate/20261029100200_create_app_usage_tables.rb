# frozen_string_literal: true

# How the iPhone and Android apps are used, counted on our own server: every
# app screen is one of our pages, so nothing goes to anyone else
# (docs/mobile_app_analytics.md; Tim, 2026-10-28).
#   app_activity_days  one row per person per day they used the app
#   app_page_days      page loads per day, platform and page, with no person
class CreateAppUsageTables < ActiveRecord::Migration[8.1]
  def up
    create_table :app_activity_days do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :day, null: false
      t.string :platform, null: false
      t.string :app_version
      t.integer :nav
      t.timestamps
    end
    add_index :app_activity_days, %i[user_id day], unique: true
    add_index :app_activity_days, :day

    create_table :app_page_days do |t|
      t.date :day, null: false
      t.string :platform, null: false
      t.string :page, null: false
      t.integer :views, null: false, default: 0
    end
    add_index :app_page_days, %i[day platform page], unique: true

    # Each person's days signing in to the app so far, so "first app day"
    # starts from their first sign-in, not from today.
    execute <<~SQL.squish
      INSERT INTO app_activity_days (user_id, day, platform, created_at, updated_at)
      SELECT DISTINCT ON (s.user_id, (s.created_at AT TIME ZONE 'UTC')::date)
             s.user_id, (s.created_at AT TIME ZONE 'UTC')::date,
             CASE WHEN s.user_agent LIKE '%Android%' THEN 'android' ELSE 'ios' END,
             NOW(), NOW()
      FROM sessions s
      JOIN users u ON u.id = s.user_id
      WHERE s.impersonator_user_id IS NULL
        AND (s.user_agent LIKE '%Turbo Native%' OR s.user_agent LIKE '%Hotwire Native%')
      ORDER BY s.user_id, (s.created_at AT TIME ZONE 'UTC')::date, s.created_at
      ON CONFLICT (user_id, day) DO NOTHING
    SQL
  end

  def down
    drop_table :app_page_days
    drop_table :app_activity_days
  end
end
