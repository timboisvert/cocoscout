# frozen_string_literal: true

# Channel for real-time ticketing engine updates
# Handles: sync progress, show status changes, sales updates, activity feed
#
# Broadcast types:
#   - engine_status: Engine status changed (active, paused, syncing)
#   - show_sync: Individual show sync progress
#   - sales_update: New ticket sales received
#   - activity: Activity feed item
#
# Usage from jobs:
#   TicketingChannel.broadcast_to(production, {
#     type: "show_sync",
#     show_id: 123,
#     status: "syncing" | "listed" | "error",
#     message: "Creating listing on Eventbrite..."
#   })
#
class TicketingChannel < ApplicationCable::Channel
  def subscribed
    @production = Production.find_by(id: params[:production_id])

    if @production && can_access_production?
      stream_for @production
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup if needed
  end

  # Client can request a manual sync
  def request_sync
    return unless @production

    TicketingSetupSyncJob.perform_later(@production.production_ticketing_setup.id)

    # Broadcast that sync was requested
    self.class.broadcast_engine_status(@production, "syncing", "Sync requested...")
  end

  # ============================================
  # Class methods for broadcasting from jobs
  # ============================================

  class << self
    # Broadcast engine status change
    def broadcast_engine_status(production, status, message = nil)
      safe_broadcast_to(production, {
        type: "engine_status",
        status: status,
        message: message,
        timestamp: Time.current.iso8601
      })
    end

    # Broadcast individual show sync progress
    def broadcast_show_sync(production, show_id, status, message = nil, provider: nil)
      safe_broadcast_to(production, {
        type: "show_sync",
        show_id: show_id,
        status: status,
        message: message,
        provider: provider,
        timestamp: Time.current.iso8601
      })
    end

    # Broadcast sales update for a show
    def broadcast_sales_update(production, show_id, sold:, available:, provider: nil)
      safe_broadcast_to(production, {
        type: "sales_update",
        show_id: show_id,
        sold: sold,
        available: available,
        provider: provider,
        timestamp: Time.current.iso8601
      })
    end

    # Broadcast activity feed item
    def broadcast_activity(production, event_type, message, show_id: nil, data: {})
      safe_broadcast_to(production, {
        type: "activity",
        event_type: event_type,
        message: message,
        show_id: show_id,
        data: data,
        timestamp: Time.current.iso8601
      })
    end

    private

    # Wrap broadcasts to handle Solid Cable compatibility issues
    def safe_broadcast_to(production, payload)
      broadcast_to(production, payload)
    rescue ArgumentError => e
      Rails.logger.warn("TicketingChannel broadcast failed: #{e.message}")
    end
  end

  private

  def can_access_production?
    return false unless current_user

    current_user.accessible_productions.exists?(id: @production.id)
  end
end
