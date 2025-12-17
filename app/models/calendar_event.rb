# frozen_string_literal: true

class CalendarEvent < ApplicationRecord
  belongs_to :calendar_subscription
  belongs_to :show

  validates :provider_event_id, presence: true
  validates :show_id, uniqueness: { scope: :calendar_subscription_id }

  # Generate a hash of the show data to detect changes
  def self.generate_sync_hash(show)
    data = {
      production_name: show.production.name,
      event_type: show.event_type,
      secondary_name: show.secondary_name,
      start: show.date_and_time&.iso8601,
      location: show.location&.full_address,
      canceled: show.canceled?,
      is_online: show.is_online?,
      online_location_info: show.online_location_info
    }
    Digest::SHA256.hexdigest(data.to_json)
  end

  # Check if the show has changed since last sync
  def show_changed?
    current_hash = self.class.generate_sync_hash(show)
    current_hash != last_sync_hash
  end

  # Mark as synced with current show data
  def mark_synced!
    update!(
      last_synced_at: Time.current,
      last_sync_hash: self.class.generate_sync_hash(show)
    )
  end
end
