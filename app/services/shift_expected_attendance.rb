# frozen_string_literal: true

# How many people to expect at the shows a shift covers, for staff who never
# see Ticketing (Staffing settings → Ticketing, staff_see_ticket_counts):
# everyone holding a ticket, comps and tickets sold on other sites included.
# Just the number: no names, no money.
#
# The shows are the shift's Shift#shows_on_duty: a show-specific shift's own
# show(s), a house shift's whole night. A show with nothing on sale is listed
# with no count.
class ShiftExpectedAttendance
  Line = Data.define(:show, :expected) do
    # "7:30 PM Stargazers", "1:30 PM Stargazers rehearsal".
    def words
      kind = show.event_type.to_s
      "#{show.date_and_time.strftime('%-l:%M %p')} #{show.production&.name}#{" #{kind.humanize.downcase}" unless kind.blank? || kind == 'show'}".strip
    end
  end

  # { shift_id => [Line, ...] }, only for shifts whose organization shows the
  # counts: the setting on, Pro, and the box office open.
  def self.for(shifts)
    shifts = Array(shifts)
    return {} if shifts.empty?

    orgs = Organization.where(id: shifts.map(&:organization_id).uniq).includes(:ticketing_profile)
    showing = orgs.select { |org| org.staff_see_ticket_counts? && org.feature_available?(:ticketing) && org.ticketing_profile&.enabled? == true }
                  .map(&:id).to_set
    shifts = shifts.select { |shift| showing.include?(shift.organization_id) }
    return {} if shifts.empty?

    targets = shifts.to_h { |shift| [ shift.id, shift.shows_on_duty ] }
    show_ids = targets.values.flatten.map(&:id).uniq
    listings = TicketListing.where(show_id: show_ids).where.not(status: %w[draft canceled]).index_by(&:show_id)
    stats = Ticketing::ListingStats.for(listings.values)
    targets.transform_values do |shows|
      shows.map do |show|
        listing = listings[show.id]
        numbers = listing && stats[listing.id]
        Line.new(show: show, expected: numbers && numbers.sold + numbers.outside_sold)
      end
    end
  end
end
