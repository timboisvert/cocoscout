# frozen_string_literal: true

# What taking dates off a contract leaves for the manager to deal with: the
# tickets people hold for each date and the staff scheduled to work it.
#
# It only reads. Removing a date never refunds a buyer or unschedules anyone
# (Tim, 2026-10-29: "Don't actually manually do it, just tell me what I need
# to do"), so the review step shows this, the manager says they'll take care
# of it, and the date goes as it always has. What's left is kept on the
# contract (draft_data["date_removal_follow_up"]) and read back live on its
# page, so each line drops off as it's fixed.
class ContractDateRemovalImpact
  FOLLOW_UP_KEY = "date_removal_follow_up"

  # One removed date: its tickets (nil when ticketing isn't on for it) and
  # the people scheduled to work it.
  Entry = Struct.new(:label, :date, :listing, :tickets, :staff, :shift_ids, keyword_init: true) do
    def tickets_to_handle?
      tickets.present? && tickets[:live].positive?
    end

    def staff_to_handle?
      staff.any?
    end

    def affected?
      tickets_to_handle? || staff_to_handle?
    end
  end

  attr_reader :entries

  # The dates about to come off, read before anything changes.
  def self.for_rentals(contract, rentals)
    rentals = Array(rentals).sort_by(&:starts_at)
    shows_by_rental = contract.production ? contract.production.shows.where(space_rental_id: rentals.map(&:id)).group_by(&:space_rental_id) : {}

    new(contract, rentals.map do |rental|
      shows = shows_by_rental[rental.id] || []
      {
        label: rental.starts_at.strftime("%a, %b %-d"),
        date: rental.starts_at.to_date,
        listings: TicketListing.where(show_id: shows.map(&:id)).to_a,
        shifts: shifts_for(shows: shows, rental_id: rental.id)
      }
    end)
  end

  # Cancelling the whole contract: one entry per show it takes away (a
  # production's shows needn't each sit in a booking), read before anything
  # goes.
  def self.for_shows(contract, shows)
    shows = Array(shows).sort_by(&:date_and_time)
    listings = TicketListing.where(show_id: shows.map(&:id)).group_by(&:show_id)

    new(contract, shows.map do |show|
      {
        label: show.date_and_time.strftime("%a, %b %-d"),
        date: show.date_and_time.to_date,
        listings: listings[show.id] || [],
        shifts: shifts_for(shows: [ show ], rental_id: show.space_rental_id)
      }
    end)
  end

  # What's still to do from the last removal, read fresh: a refunded order or
  # an unscheduled person is simply not there any more.
  def self.follow_up(contract)
    saved = Array((contract.draft_data || {})[FOLLOW_UP_KEY])
    return new(contract, []) if saved.empty?

    listings = TicketListing.where(id: saved.flat_map { |s| Array(s["listing_ids"]) }).index_by(&:id)
    shifts = Shift.where(id: saved.flat_map { |s| Array(s["shift_ids"]) }).index_by(&:id)

    new(contract, saved.map do |s|
      {
        label: s["label"],
        date: (Date.iso8601(s["date"].to_s) rescue nil),
        listings: Array(s["listing_ids"]).filter_map { |id| listings[id] },
        shifts: Array(s["shift_ids"]).filter_map { |id| shifts[id] }
      }
    end)
  end

  # A date's shifts: those generated for its show (or merged to cover it), and
  # those made for the booking itself.
  def self.shifts_for(shows:, rental_id:)
    show_ids = shows.map(&:id)
    scope = Shift.where(source_type: "SpaceRental", source_id: rental_id)
    if show_ids.any?
      scope = scope.or(Shift.where(source_type: "Show", source_id: show_ids))
                   .or(Shift.where(id: ShiftShow.where(show_id: show_ids).select(:shift_id)))
    end
    scope.to_a
  end

  def initialize(contract, dates)
    organization = contract.organization
    ticketing = organization.feature_available?(:ticketing)
    staffing = @staffing_on = organization.feature_available?(:staffing)

    all_shifts = dates.flat_map { |d| d[:shifts] }
    ActiveRecord::Associations::Preloader.new(
      records: all_shifts, associations: [ :house_role, :additional_roles, { shift_assignments: :person } ]
    ).call

    @entries = dates.map do |date|
      listing = date[:listings].first
      Entry.new(
        label: date[:label],
        date: date[:date],
        listing: listing,
        tickets: (ticket_summary(date[:listings]) if ticketing && listing),
        staff: staffing ? staff_summary(date[:shifts]) : [],
        shift_ids: date[:shifts].map(&:id)
      )
    end
  end

  def affected
    entries.select(&:affected?)
  end

  def any?
    affected.any?
  end

  # Ticketing is on for at least one of these dates, so "no tickets sold" is
  # worth saying.
  def ticketing_on?
    entries.any? { |e| e.tickets.present? }
  end

  # Staffing is a Pro module; without it there's nobody scheduled to mention.
  def staffing_on?
    @staffing_on
  end

  # What to keep on the contract for its page to read back. Only the dates
  # with something to do.
  def to_follow_up
    affected.map do |e|
      { "label" => e.label, "date" => e.date&.iso8601,
        "listing_ids" => [ e.listing&.id ].compact, "shift_ids" => e.shift_ids }
    end
  end

  private

  # Tickets still good on this date, split into paid and comps, and the money
  # buyers have in them. "Sold" is TicketListing#worth_keeping?'s: an
  # abandoned checkout or a comp given back isn't anything to deal with.
  def ticket_summary(listings)
    paid = comps = money = outside = 0
    listings.each do |listing|
      listing.orders_worth_keeping.each do |order|
        live = order.tickets.count { |t| t.status.in?(Ticket::SOLD_STATUSES) }
        next if live.zero?

        if order.money_path == "none"
          comps += live
        else
          paid += live
          money += order.total_cents.to_i - order.refunded_cents.to_i
        end
      end
      outside += listing.ticket_outside_sales.sum(:tickets_sold)
    end
    { paid: paid, comps: comps, live: paid + comps, money_cents: money, outside: outside }
  end

  # Everyone still on one of these shifts (not those who already said they
  # can't make it), with the role and the hours.
  def staff_summary(shifts)
    shifts.sort_by(&:starts_at).flat_map do |shift|
      shift.active_assignments.filter_map do |assignment|
        next unless assignment.person

        { name: assignment.person.name, role: shift.role_label,
          starts_at: shift.starts_at, ends_at: shift.ends_at }
      end
    end
  end
end
