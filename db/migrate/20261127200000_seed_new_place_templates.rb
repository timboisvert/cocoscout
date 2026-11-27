# frozen_string_literal: true

# A date moved to another place at the same time (Cancel or move this date,
# Tim 2026-11-27): the cast and staff notices for it, and the buyers' email
# reworded to say what changed (date, time, place) rather than always "date
# and time", without the click-to-refund link (Tim, 2026-11-27: someone the change doesn't work for replies to the email), and a notice that said "that night" of a date that may be a matinee. Rendering a missing key raises, so they're seeded here;
# content_templates is the only table read.
class SeedNewPlaceTemplates < ActiveRecord::Migration[8.1]
  KEYS = %w[show_new_place shift_new_place].freeze

  def up
    DateChangeTemplates.ensure!(keys: KEYS)
    DateChangeTemplates.ensure!(keys: %w[date_change_buyers_moved date_change_buyers_rebooked date_change_role_opened], overwrite: true)
  end

  def down
    ContentTemplate.where(key: KEYS).delete_all
  end
end
