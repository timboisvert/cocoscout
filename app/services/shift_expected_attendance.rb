# frozen_string_literal: true

# How many people to expect at the shows a shift covers, for staff who never
# see Ticketing (Staffing settings → Ticketing, staff_see_ticket_counts):
# everyone holding a ticket, comps and tickets sold on other sites included.
# Just the number: no names, no money.
#
# A shift covers the shows it's tied to (Shift#covered_shows); a house shift
# with none covers the organization's shows it overlaps, the rule the
# scheduling page uses for coverage. A show with nothing on sale is listed
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

    targets = shifts.to_h do |shift|
      covered = shift.covered_shows
      covered = overlapping_shows(shift) if covered.empty?
      [ shift.id, covered.reject(&:canceled).uniq.sort_by(&:date_and_time) ]
    end
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

  # The organization's shows a house shift overlaps (a show that starts before
  # the shift ends and ends after it starts).
  def self.overlapping_shows(shift)
    Show.joins(:production).where(productions: { organization_id: shift.organization_id }, canceled: false)
        .where("shows.date_and_time < ? AND shows.date_and_time > ?", shift.ends_at, shift.starts_at - 12.hours)
        .includes(:production, :space_rental).to_a
        .select { |show| shift.starts_at < show.ends_at && shift.ends_at > show.date_and_time }
  end
  private_class_method :overlapping_shows
end
