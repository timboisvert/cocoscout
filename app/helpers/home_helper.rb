# frozen_string_literal: true

# Production Home, show by show (Design B, Tim 2026-10-27): each show's
# three state chips, and the tones the status bar's pills wear.
module HomeHelper
  CHIP_TONES = {
    ok: "bg-green-50 border-green-200 text-green-700",
    warn: "bg-amber-50 border-amber-200 text-amber-700",
    bad: "bg-red-50 border-red-200 text-red-700",
    live: "bg-pink-500 border-pink-500 text-white",
    none: "bg-gray-50 border-gray-200 text-gray-600"
  }.freeze

  PILL_TONES = {
    red: "border-red-200 bg-red-50 text-red-800",
    amber: "border-amber-200 bg-amber-50 text-amber-900",
    pink: "border-pink-200 bg-pink-50 text-pink-900",
    green: "border-green-200 bg-green-50 text-green-900",
    gray: "border-gray-200 bg-white text-gray-700"
  }.freeze

  PILL_DOTS = { red: "bg-red-600", amber: "bg-amber-500", pink: "bg-pink-500", green: "bg-green-500", gray: "bg-gray-400" }.freeze

  # [tone, short words, long words] for a show's tickets, or nil without any.
  def home_ticket_chip(tickets)
    return nil unless tickets

    stats = tickets.stats
    if tickets.canceled?
      stats.sold.positive? ? [ :bad, "#{stats.sold} to refund", "#{stats.sold} hold tickets · refund them" ] : [ :none, "Canceled", "Canceled" ]
    elsif tickets.draft?
      [ :warn, "Not on sale", "Not on sale yet" ]
    elsif tickets.live?
      [ :live, "#{stats.checked_in} in · #{stats.sold}", "#{stats.checked_in} checked in · #{stats.sold} sold" ]
    elsif tickets.sold_out?
      [ :ok, "Sold out", "Sold out · #{stats.sold} · #{number_to_currency(stats.gross_cents / 100.0, precision: 0)}" ]
    else
      of = stats.capacity ? " of #{stats.capacity}" : ""
      [ :none, stats.sold.to_s, "#{stats.sold} sold#{of} · #{number_to_currency(stats.gross_cents / 100.0, precision: 0)}" ]
    end
  end

  def home_staffing_chip(staffing)
    return nil unless staffing

    if staffing.none?
      [ :warn, "No shifts", "No shifts yet" ]
    elsif staffing.declined.positive?
      [ :bad, "#{staffing.staffed}/#{staffing.total} · #{staffing.declined} can't", "#{staffing.staffed} of #{staffing.total} · #{staffing.declined} can't make it" ]
    elsif staffing.total.zero?
      [ :ok, "Covered", "Covered" ]
    elsif staffing.open.positive?
      [ :warn, "#{staffing.staffed}/#{staffing.total}", "#{staffing.staffed} of #{staffing.total} staffed · #{staffing.open} open" ]
    else
      [ :ok, "#{staffing.staffed}/#{staffing.total}", "Fully staffed · #{staffing.total}" ]
    end
  end

  def home_cast_chip(cast)
    return nil unless cast

    if cast.vacancies.any?
      n = cast.vacancies.size
      [ :bad, "#{n} open", "#{n} #{'vacancy'.pluralize(n)} · #{cast.vacancies.map { |v| v.role&.name }.compact.join(', ')}" ]
    elsif cast.uncast.positive?
      [ :warn, "#{cast.uncast} uncast", "#{cast.uncast} #{'role'.pluralize(cast.uncast)} uncast" ]
    elsif cast.unnotified.positive?
      [ :warn, "#{cast.unnotified} to notify", "#{cast.unnotified} not notified yet" ]
    else
      [ :ok, "Cast", "All cast · #{cast.assigned}" ]
    end
  end

  # The Home path for a day or a week, keeping the 7-day / 3-day choice.
  def home_day_path(day, days: @home_days)
    days == 3 ? manage_path(day: day.iso8601, days: 3) : manage_path(day: day.iso8601)
  end

  def home_week_path(monday)
    manage_path(week_start: monday.to_s, days: 7)
  end
end
