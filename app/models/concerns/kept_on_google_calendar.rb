# frozen_string_literal: true

# A show or a rental that the organization's Google Calendar carries: any
# change to it (made, moved, renamed, canceled, deleted) reaches the
# calendar, when the organization has one connected.
module KeptOnGoogleCalendar
  extend ActiveSupport::Concern

  included do
    after_commit :keep_google_calendar
  end

  private

  def keep_google_calendar
    organization_id = google_calendar_organization_id
    return unless GoogleCalendarSync.on_for?(organization_id)

    GoogleCalendarSyncJob.perform_later(organization_id, self.class.name, id)
  end
end
