# frozen_string_literal: true

# Removes one event from a person's external (Google) calendar after the show —
# and its local CalendarEvent mapping row — are already gone. Enqueued from
# Show#enqueue_remote_calendar_event_cleanup, so it works from the raw
# provider_event_id rather than a CalendarEvent record.
class CalendarEventCleanupJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(subscription_id, provider_event_id)
    subscription = CalendarSubscription.find_by(id: subscription_id)
    return unless subscription&.provider == "google"

    CalendarSync::GoogleService.new(subscription).delete_remote_event(provider_event_id)
  end
end
