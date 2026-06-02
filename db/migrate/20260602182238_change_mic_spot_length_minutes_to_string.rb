# frozen_string_literal: true

# Producers want to write fuzzy spot lengths like "3-5 minutes" or
# "3ish" — same reasoning as the recent `signup_cap` switch. Convert to
# a string column, preserving existing integer values as their text
# representation.
class ChangeMicSpotLengthMinutesToString < ActiveRecord::Migration[8.1]
  def up
    change_column :mics, :spot_length_minutes, :string, using: "spot_length_minutes::text"
  end

  def down
    execute <<~SQL.squish
      UPDATE mics SET spot_length_minutes = NULL
       WHERE spot_length_minutes !~ '^[0-9]+$'
    SQL
    change_column :mics, :spot_length_minutes, :integer, using: "spot_length_minutes::integer"
  end
end
