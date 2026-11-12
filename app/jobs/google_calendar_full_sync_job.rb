# frozen_string_literal: true

# The whole calendar for one organization: on connecting, on Sync now, when
# its settings change, and every night with force, which writes every coming
# event again so anything edited in Google is put back.
class GoogleCalendarFullSyncJob < ApplicationJob
  queue_as :background
  # One pass at a time for an organization: two at once would each write the
  # same dates, and together trip Google's limit.
  limits_concurrency to: 1, key: ->(organization_id, *) { "google-calendar-#{organization_id}" }, duration: 30.minutes
  # Google said slow down even after the pass waited: come back in a few
  # minutes. What was written is kept, so the next try starts from there.
  retry_on GoogleCalendarApi::RateLimited, wait: 5.minutes, attempts: 6
  retry_on GoogleCalendarApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(organization_id, force: false)
    GoogleCalendarSync.for(organization_id)&.sync_all!(force: force)
  end
end
