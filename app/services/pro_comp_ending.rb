# frozen_string_literal: true

# An organization's complimentary Pro is ending (Tim, 2026-11-01): two weeks
# and three days before, its billing contacts hear what Pro has done for it
# lately and what staying costs, and its Billing tab says the same with Keep
# Pro. Nothing switches to paid unless they choose it; if they don't, they
# drop to Producer when the comp ends, and their last month's usage is still
# billed (StaffMeterService.sync_usage_subscription!).
class ProCompEnding
  WARN_WITHIN = 30.days
  REMINDERS = { "two_weeks" => 14.days, "three_days" => 3.days }.freeze
  WINDOW = 90.days

  # What Pro gives an organization, for the "what you'd lose" list.
  PRO_UNLOCKS = [
    "Unlimited productions, shows and events",
    "Ticketing, with ticket money that pays your people with no bank debit",
    "Money: show financials, payout runs, contracts and advances",
    "Staffing: shifts, onboarding and paying your staff",
    "Auditions, casting tables and company-wide reports"
  ].freeze

  attr_reader :organization

  def initialize(organization, now: Time.current)
    @organization = organization
    @now = now
  end

  # A comp with an end date, still running, that nothing paid follows.
  def applies?
    org = organization
    return false if org.comped_indefinitely? || org.comped_until.blank? || org.comped_until <= @now
    return false if org.pro_on_monthly_bill?(org.comped_until + 1.second)

    !org.subscription_status.in?(SubscriptionSyncService::ACCESS_STATUSES)
  end

  def ending_soon? = applies? && organization.comped_until <= @now + WARN_WITHIN
  def ends_on = organization.comped_until.to_date
  def days_left = [ (ends_on - @now.to_date).to_i, 0 ].max

  # What Pro did for them over the last 90 days, in their own numbers, each a
  # short sentence; only what happened.
  def value_lines
    @value_lines ||= begin
      since = [ @now - WINDOW, organization.created_at ].max
      lines = []
      orders = TicketOrder.where(organization: organization, money_path: "cocoscout", exchanged_from_id: nil, paid_at: since..@now).where("total_cents > 0")
      tickets = orders.sum(:platform_fee_cents) / TicketPricing::PLATFORM_FEE_CENTS
      if tickets.positive?
        lines << "Sold #{number(tickets)} #{'ticket'.pluralize(tickets)} (#{money(orders.sum(:total_cents))}), with the money right in your CocoScout balance"
      end
      items = PayoutBatchItem.paid.where.not(stripe_transfer_id: nil).joins(:payout_batch)
                             .where(payout_batches: { organization_id: organization.id }, paid_at: since..@now)
      people = items.distinct.count(:payee_id)
      lines << "Paid #{number(people)} #{'person'.pluralize(people)} #{money(items.sum(:amount_cents))} straight to their banks" if people.positive?
      shows = Show.joins(:production).where(productions: { organization_id: organization.id }, canceled: false, date_and_time: since..@now).count
      lines << "Ran #{number(shows)} #{'show'.pluralize(shows)} and events" if shows.positive?
      shifts = Shift.where(organization: organization, starts_at: since..@now).count
      lines << "Scheduled #{number(shifts)} staff #{'shift'.pluralize(shifts)}" if shifts.positive?
      lines
    end
  end

  # What Pro costs from the day the comp ends, in words.
  def price_line
    "Pro is #{money(SubscriptionPlan::PRO_MONTHLY_CENTS)} a month on your one monthly bill (or #{money(SubscriptionPlan::PRO_ANNUAL_CENTS)} a year, " \
      "saving $#{SubscriptionPlan.annual_savings_dollars}), plus usage: $5 for each staff member and $3 for everyone else you pay through CocoScout that month."
  end

  # Reminders to send now: the stages whose time has come and that haven't
  # gone for this comp's end date.
  def due_reminders
    return [] unless applies?

    sent = Array(organization.comp_reminders.to_h[ends_on.iso8601])
    REMINDERS.select { |stage, before| ends_on <= (@now + before).to_date && !sent.include?(stage) }.keys.last(1)
  end

  def mark_sent!(stage)
    reminders = organization.comp_reminders.to_h
    reminders[ends_on.iso8601] = (Array(reminders[ends_on.iso8601]) + [ stage ]).uniq
    organization.update_column(:comp_reminders, reminders)
  end

  # The email's variables.
  def email_variables(first_name)
    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    list = ->(items) { "<ul>#{items.map { |item| "<li>#{ERB::Util.html_escape(item)}</li>" }.join}</ul>" }
    {
      "first_name" => first_name.presence || "there",
      "organization_name" => organization.name,
      "ends_on" => ends_on.strftime("%B %-d"),
      "days_left" => days_left == 1 ? "1 day" : "#{days_left} days",
      "value_lines" => value_lines.any? ? "<p>In the last three months, with Pro, #{ERB::Util.html_escape(organization.name)}:</p>#{list.call(value_lines)}" : "",
      "price_line" => price_line,
      "lose_lines" => list.call(PRO_UNLOCKS),
      "keep_url" => Rails.application.routes.url_helpers.section_manage_organization_url(organization, section: "billing", **url_options)
    }
  end

  private

  def money(cents) = ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, precision: (cents % 100).zero? ? 0 : 2)
  def number(count) = ActiveSupport::NumberHelper.number_to_delimited(count)
end
