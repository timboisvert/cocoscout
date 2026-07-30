# frozen_string_literal: true

# Detects scheduling conflicts for a contract's *draft* bookings — before any
# space rentals are created — so the wizard can warn the producer up front
# instead of failing at activation.
#
# It mirrors SpaceRental#no_overlapping_rentals (same 1-minute back-to-back
# buffer, same "standalone shows only" rule) but returns structured data rather
# than error strings, so the review page can render a real day-by-day calendar
# of what's already scheduled and explain the clash in plain English.
class ContractBookingConflicts
  BUFFER = 1.minute
  # Shows carry only a start time, so give them a nominal block on the calendar.
  DEFAULT_SHOW_MINUTES = 120

  # One block on a day's timeline (an existing rental/show, or a proposed booking).
  Block = Struct.new(:label, :sublabel, :starts_at, :ends_at, :kind, keyword_init: true) do
    # kind: :proposed (this contract), :existing (someone else), and either may be
    # flagged :conflict when the two actually overlap.
    def conflicting? = kind == :proposed_conflict || kind == :existing_conflict
    def proposed? = kind == :proposed || kind == :proposed_conflict
  end

  # A single space+date that has at least one overlap, with the full day's schedule.
  ConflictDay = Struct.new(:date, :space_name, :location_name, :blocks, keyword_init: true) do
    def proposed_blocks = blocks.select(&:proposed?)
    def conflicting_existing = blocks.select { |b| b.kind == :existing_conflict }

    # Plain-English description of what clashes on this day.
    def plain_english
      mine = proposed_blocks.select(&:conflicting?)
      return "" if mine.empty?

      others = conflicting_existing
      other_desc = others.map { |b| "#{b.label} (#{ContractBookingConflicts.time_range(b)})" }.to_sentence
      mine_desc = mine.map { |b| ContractBookingConflicts.time_range(b) }.to_sentence

      "Your booking on #{date.strftime('%A, %b %-d')} (#{mine_desc}) overlaps with " \
      "#{other_desc} already scheduled in #{space_name}."
    end
  end

  def self.time_range(block)
    "#{block.starts_at.strftime('%-l:%M %p').strip}–#{block.ends_at.strftime('%-l:%M %p').strip}"
  end

  def initialize(contract)
    @contract = contract
    @org = contract.organization
  end

  def any?
    conflict_days.any?
  end

  # How many of the contract's proposed bookings clash (for the summary bar).
  def count
    conflict_days.sum { |d| d.proposed_blocks.count(&:conflicting?) }
  end

  # Space+date groups that contain a real overlap, each with the full day timeline.
  def conflict_days
    @conflict_days ||= build
  end

  private

  # Parse the draft bookings into comparable proposed rentals. Both specific-room
  # and "entire venue" bookings are included (space_id nil means entire venue) —
  # an entire-venue booking conflicts with every space at the location, so it can't
  # be skipped, matching SpaceRental#no_overlapping_rentals.
  def proposed_rentals
    @proposed_rentals ||= @contract.draft_bookings.filter_map do |b|
      location_id = b["location_id"].presence
      next if location_id.blank?

      starts_at = safe_parse(b["starts_at"])
      next if starts_at.nil?

      ends_at = if b["ends_at"].present?
                  safe_parse(b["ends_at"])
      else
                  starts_at + b["duration"].to_f.hours
      end
      next if ends_at.nil? || ends_at <= starts_at

      space_id = (b["location_space_id"] || b["space_id"]).presence
      { location_id: location_id.to_i, space_id: space_id&.to_i, starts_at: starts_at, ends_at: ends_at }
    end
  end

  def build
    return [] if proposed_rentals.empty?

    locations_map = @org.locations.includes(:location_spaces).index_by(&:id)

    # Group proposed bookings by location + space (nil = entire venue) + day.
    groups = proposed_rentals.group_by { |r| [ r[:location_id], r[:space_id], r[:starts_at].to_date ] }

    groups.filter_map do |(location_id, space_id, date), proposed|
      location = locations_map[location_id]
      next if location.nil?

      space = space_id && location.location_spaces.find { |s| s.id == space_id }
      next if space_id && space.nil? # a specific space we don't recognize

      day_start = date.in_time_zone.beginning_of_day
      day_end   = date.in_time_zone.end_of_day

      existing = existing_blocks(location_id, space_id, day_start, day_end)
      next if existing.empty?

      proposed_blocks = proposed.map do |r|
        clashes = existing.any? { |e| overlap?(r[:starts_at], r[:ends_at], e[:starts_at], e[:ends_at]) }
        Block.new(label: "This contract", sublabel: @contract.production_name.presence || @contract.contractor_name,
                  starts_at: r[:starts_at], ends_at: r[:ends_at],
                  kind: clashes ? :proposed_conflict : :proposed)
      end

      # Only surface this day if a proposed booking actually overlaps something.
      next unless proposed_blocks.any?(&:conflicting?)

      existing_blocks_out = existing.map do |e|
        clashes = proposed.any? { |r| overlap?(r[:starts_at], r[:ends_at], e[:starts_at], e[:ends_at]) }
        Block.new(label: e[:label], sublabel: e[:sublabel],
                  starts_at: e[:starts_at], ends_at: e[:ends_at],
                  kind: clashes ? :existing_conflict : :existing)
      end

      all_blocks = (proposed_blocks + existing_blocks_out).sort_by(&:starts_at)

      ConflictDay.new(date: date, space_name: space&.name || "Entire Venue",
                      location_name: location.name,
                      blocks: all_blocks)
    end.sort_by(&:date)
  end

  # Everything already on the calendar at an intersecting space that day: other
  # contracts' rentals plus standalone shows (shows tied to a rental are counted
  # via the rental, matching SpaceRental#no_overlapping_rentals). space_id nil
  # (entire venue) intersects every space at the location.
  def existing_blocks(location_id, space_id, day_start, day_end)
    rentals = SpaceRental
      .joins(:contract)
      .includes(:contract, :location_space)
      .where(location_id: location_id)
      .where.not(contract_id: @contract.id)
      .where.not(contracts: { status: "cancelled" })
      .where("space_rentals.starts_at < ? AND space_rentals.ends_at > ?", day_end, day_start)
    rentals = rentals.where(location_space_id: [ space_id, nil ]) if space_id.present?

    rental_blocks = rentals.map do |r|
      name = r.contract.production_name.presence || r.contract.contractor_name
      { label: name.presence || "Booked", sublabel: existing_space_label(r.location_space),
        starts_at: r.starts_at, ends_at: r.ends_at }
    end

    shows = Show
      .includes(:location_space)
      .where(location_id: location_id, canceled: false, space_rental_id: nil)
      .where("date_and_time >= ? AND date_and_time <= ?", day_start, day_end)
    shows = shows.where(location_space_id: [ space_id, nil ]) if space_id.present?

    show_blocks = shows.map do |s|
      { label: s.display_name.presence || "Event", sublabel: existing_space_label(s.location_space),
        starts_at: s.date_and_time, ends_at: s.date_and_time + DEFAULT_SHOW_MINUTES.minutes }
    end

    (rental_blocks + show_blocks).sort_by { |b| b[:starts_at] }
  end

  # Name the existing booking's own space so the producer can see whether the clash
  # is the same room or an "entire venue" hold that swallows it.
  def existing_space_label(location_space)
    location_space&.name || "Entire Venue"
  end

  # Same back-to-back buffer as the model validation.
  def overlap?(a_start, a_end, b_start, b_end)
    a_start < (b_end - BUFFER) && a_end > (b_start + BUFFER)
  end

  def safe_parse(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
