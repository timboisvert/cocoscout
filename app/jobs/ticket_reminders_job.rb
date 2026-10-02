# frozen_string_literal: true

# Reminders before the show (Ticketing settings → Box office → Reminder
# email). Every morning, buyers whose show is the theater's chosen number of
# days away get the time, the place and their tickets again. Each order is
# reminded once — stamped before its email is queued, so a rerun never sends
# twice — and buyers who stopped reminders, or bought in the last few hours
# (their confirmation just arrived), are skipped.
class TicketRemindersJob < ApplicationJob
  queue_as :default

  JUST_BOUGHT = 12.hours

  def perform(today = Date.current)
    TicketingProfile.where(enabled: true).where.not(reminder_days_before: nil).find_each do |profile|
      self.class.due(profile, today).find_each do |order|
        next unless TicketOrder.where(id: order.id, reminded_at: nil).update_all(reminded_at: Time.current) == 1

        TicketOrderMailer.reminder(order).deliver_later
      end
    rescue StandardError => e
      Rails.logger.error("[TicketRemindersJob] org #{profile.organization_id}: #{e.class}: #{e.message}")
    end
  end

  # Orders to remind today: their show is reminder_days_before days away.
  def self.due(profile, today = Date.current)
    day = today + profile.reminder_days_before
    listings = TicketListing.where(organization_id: profile.organization_id).where.not(status: %w[draft canceled])
                            .joins(:show).where(shows: { canceled: false, date_and_time: day.all_day })
    TicketOrder.paid_like.where(ticket_listing_id: listings.select(:id), reminded_at: nil, reminders_opt_out: false)
               .where.not(buyer_email: nil).where(paid_at: ...JUST_BOUGHT.ago)
  end
end
