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

      producer_notes(organization, profile) if profile.producer_daily_emails
    rescue StandardError => e
      Rails.logger.error("[TicketingDailyNoticesJob] org #{profile.organization_id}: #{e.class}: #{e.message}")
    end
  end

  # Producers who asked for a morning note: their coming shows at this
  # theater and how each is selling (ticket_sales_producer_daily).
  def producer_notes(organization, _profile)
    users = User.where(id: TicketSalesViewer.active.where(organization_id: organization.id, daily_email: true).select(:user_id))
    users.find_each do |user|
      listings = TicketSalesAccess.listings_for(user).where(organization_id: organization.id)
                                  .where("shows.date_and_time >= ?", Time.current).order("shows.date_and_time").limit(15).to_a
      next if listings.empty?

      stats = Ticketing::ListingStats.for(listings)
      rows = listings.map do |listing|
        %(<tr><td style="padding:4px 12px 4px 0">#{listing.show.date_and_time.strftime('%a %b %-d')} · #{ERB::Util.html_escape(listing.display_title)}</td>) +
          %(<td style="padding:4px 0;text-align:right">#{TicketingNotificationContent.sold_line(stats[listing.id])}</td></tr>)
      end
      AppMailer.with(template_key: "ticket_sales_producer_daily", to: user.email_address, variables: {
        first_name: user.person&.name.to_s.split.first.presence || "there",
        organization_name: organization.name,
        rows: "<table>#{rows.join}</table>",
        sales_url: Rails.application.routes.url_helpers.my_ticket_sales_url(**mailer_url_options)
      }).send_template.deliver_later
    end
  end

  def mailer_url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
