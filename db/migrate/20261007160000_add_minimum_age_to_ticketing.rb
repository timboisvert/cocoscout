# frozen_string_literal: true

# A minimum age for a production's shows, with a date's own when it differs
# (Tim, 2026-10-07). On a production, blank is all ages; on a date, blank
# follows the production and 0 is all ages for that date. A free-text "Ages"
# note that was only an age ("21+", "18 and over") becomes the number; any
# other words stay as the note beside it.
class AddMinimumAgeToTicketing < ActiveRecord::Migration[8.1]
  AGE_ONLY = /\A\s*(?:ages?\s*)?(\d{1,2})\s*(?:\+|and (?:over|up|older)|or older)?\s*\.?\s*\z/i

  def up
    add_column :production_ticketings, :minimum_age, :integer
    add_column :ticket_listings, :minimum_age, :integer

    %w[production_ticketings ticket_listings].each do |table|
      select_rows("SELECT id, age_note FROM #{table} WHERE age_note IS NOT NULL AND age_note <> ''").each do |id, note|
        age = note[AGE_ONLY, 1]&.to_i
        next unless age&.between?(1, 99)

        execute("UPDATE #{table} SET minimum_age = #{age}, age_note = NULL WHERE id = #{id.to_i}")
      end
    end
  end

  def down
    remove_column :ticket_listings, :minimum_age
    remove_column :production_ticketings, :minimum_age
  end
end
