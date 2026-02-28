# frozen_string_literal: true

# Stores ticketing engine activity for history and live feed
# Activities are broadcast via TicketingChannel when created
class TicketingActivity < ApplicationRecord
  belongs_to :production
  belongs_to :show, optional: true  # Nullable for production-level activities

  # Event types:
  #   sync_started, sync_complete, listing_created, listing_updated,
  #   listing_error, sales_received, inventory_updated, error
  validates :event_type, presence: true
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :for_production, ->(production_id) { where(production_id: production_id).recent }

  # Create and broadcast an activity
  def self.log!(production, event_type, message, show: nil, data: {})
    activity = create!(
      production: production,
      show: show,
      event_type: event_type,
      message: message,
      data: data
    )

    # Broadcast to connected clients
    TicketingChannel.broadcast_activity(
      production,
      event_type,
      message,
      show_id: show&.id,
      data: data
    )

    activity
  end

  # Prune old activities (run via scheduled job)
  def self.prune_old!(days: 7)
    where("created_at < ?", days.days.ago).delete_all
  end
end
