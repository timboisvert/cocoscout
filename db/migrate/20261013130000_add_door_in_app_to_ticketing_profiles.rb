# frozen_string_literal: true

# When the Door shows in the CocoScout app's menu (Ticketing settings → Door):
# "smart" from show day (or door_hours_before the show) until it's over, or
# "always" for people with door access.
class AddDoorInAppToTicketingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :door_in_app, :string, default: "smart", null: false
    add_column :ticketing_profiles, :door_hours_before, :integer
  end
end
