# frozen_string_literal: true

# Daily Ticketing notices for every theater selling: the morning summary of
# yesterday's sales (7am) and each show-day note (sent once per show, the day
# of it). Theaters with ticketing switched off get nothing.
class TicketingDailyNoticesJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    TicketingProfile.where(enabled: true).includes(:organization).find_each do |profile|
      organization = profile.organization
      summary = TicketingNotificationContent.daily_summary(organization, today - 1)
      if summary.delete(:anything)
        TicketingNotifier.notify(organization, :daily_summary, variables: summary, occasion: today.iso8601, once: true)
      end

      organization.ticket_listings.joins(:show).where.not(status: %w[draft canceled])
                  .where(shows: { canceled: false, date_and_time: today.all_day }).find_each do |listing|
        TicketingNotifier.notify(organization, :show_day, variables: TicketingNotificationContent.show_day(listing),
                                                          about: listing, occasion: today.iso8601, once: true)
      end
    rescue StandardError => e
      Rails.logger.error("[TicketingDailyNoticesJob] org #{profile.organization_id}: #{e.class}: #{e.message}")
    end
  end
end
