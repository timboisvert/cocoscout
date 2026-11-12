# frozen_string_literal: true

# Every night, every organization with a Google Calendar: the full pass with
# force, so the calendar is what CocoScout says whatever happened in Google.
class GoogleCalendarNightlyJob < ApplicationJob
  queue_as :background

  def perform
    Integration.google_calendar.where(status: %w[connected error]).pluck(:organization_id).each do |organization_id|
      GoogleCalendarFullSyncJob.perform_later(organization_id, force: true)
    end
  end
end
