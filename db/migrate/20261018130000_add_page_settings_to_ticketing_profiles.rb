# frozen_string_literal: true

# The organization's box office page (Tim, 2026-10-18): which layout it
# uses, a welcome line, and whether the venue's address shows. The wide
# image is an attachment (HasWideImage).
class AddPageSettingsToTicketingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :box_office_layout, :string, null: false, default: "dates"
    add_column :ticketing_profiles, :welcome_line, :string
    add_column :ticketing_profiles, :show_address, :boolean, null: false, default: true
  end
end
