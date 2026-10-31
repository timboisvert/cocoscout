# frozen_string_literal: true

# Rooms belong to every plan (advanced ticketing plan §0, Tim 2026-10-29):
# every location has at least one room, a show with a location lands in a
# room, and Ticketing keeps its own per-room settings in its own table, so
# nothing on a room depends on ticketing.
class RoomsForEveryLocation < ActiveRecord::Migration[8.1]
  def up
    create_table :room_ticketing_settings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :location_space, null: false, foreign_key: true, index: { unique: true }
      t.string :seating_mode, null: false, default: "general"
      t.bigint :default_seat_chart_id
      t.text :buyer_directions
      t.timestamps
    end

    # Every location gets a room; it becomes the default (the only one).
    execute <<~SQL
      INSERT INTO location_spaces (location_id, name, "default", created_at, updated_at)
      SELECT l.id, 'Main room', TRUE, NOW(), NOW()
      FROM locations l
      WHERE NOT EXISTS (SELECT 1 FROM location_spaces s WHERE s.location_id = l.id)
    SQL
    # A location with rooms but no default: its first room is.
    execute <<~SQL
      UPDATE location_spaces s SET "default" = TRUE
      WHERE s.id = (SELECT MIN(id) FROM location_spaces s2 WHERE s2.location_id = s.location_id)
        AND NOT EXISTS (SELECT 1 FROM location_spaces d WHERE d.location_id = s.location_id AND d."default" = TRUE)
    SQL
    # A show with a location but no room lands in the location's default room.
    execute <<~SQL
      UPDATE shows SET location_space_id = d.id
      FROM location_spaces d
      WHERE shows.location_id = d.location_id AND d."default" = TRUE AND shows.location_space_id IS NULL
    SQL
  end

  def down
    drop_table :room_ticketing_settings
  end
end
