# frozen_string_literal: true

# The whole calendar for one organization: on connecting, on Sync now, when
# its settings change, and every night with force, which writes every coming
# event again so anything edited in Google is put back.
class GoogleCalendarFullSyncJob < ApplicationJob
  queue_as :background
  retry_on GoogleCalendarApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(organization_id, force: false)
    GoogleCalendarSync.for(organization_id)&.sync_all!(force: force)
  end
end
