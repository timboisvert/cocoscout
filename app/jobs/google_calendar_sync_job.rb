# frozen_string_literal: true

# One show or rental changed: its event on the organization's Google
# Calendar is written again, or taken off.
class GoogleCalendarSyncJob < ApplicationJob
  queue_as :background
  limits_concurrency to: 1, key: ->(organization_id, *) { "google-calendar-#{organization_id}" }, duration: 30.minutes
  retry_on GoogleCalendarApi::Error, wait: :polynomially_longer, attempts: 4
  discard_on GoogleCalendarApi::Unauthorized

  def perform(organization_id, type, id)
    GoogleCalendarSync.for(organization_id)&.sync_record!(type, id)
  end
end
