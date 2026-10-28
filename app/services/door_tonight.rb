# frozen_string_literal: true

# The shows someone could be working the door for right now: the app's menu
# offers the Door only then (Tim, 2026-10-13), instead of as a tile every day.
# Each organization chooses in Ticketing settings → Door (door_in_app):
# "smart", the window below, or "always", where the menu keeps the Door and
# names the next show when none is on.
#
# A show's door is open from the morning of the show (or 12 hours before, for
# a show after midnight), or door_hours_before it when the organization sets
# that, until an hour after it ends. A show with no end time set stays open
# until 2 AM the night of the show, since nobody can say when it's done.
module DoorTonight
  ENDS_LATE = 2 # o'clock, the morning after a show with no end time
  AFTER_END = 1.hour
  # Before this hour, a show belongs to the night before (a 1 AM show is Friday night's).
  NIGHT_ROLLOVER = 6
  # The arrival rush (Tim, 2026-10-24): an hour before a show starts until half
  # an hour after, when people are actually at the door. The Door's list gives
  # these the big pink card; every other open door is a small one.
  ARRIVING_BEFORE = 1.hour
  ARRIVING_AFTER = 30.minutes

  def self.listings_for(user, at: Time.current)
    listings(TicketingDoorAccess.organizations_for(user).map(&:id))
      .where(shows: { date_and_time: (at - 1.day)..(at + 1.day) })
      .includes(organization: :ticketing_profile).to_a
      .select { |listing| (w = window(listing.show, listing.organization.ticketing_profile)) && w.begin <= at && at < w.end }
  end

  # Whether one of the user's organizations keeps the Door in the app's menu
  # all the time.
  def self.always?(user)
    TicketingProfile.where(organization: TicketingDoorAccess.organizations_for(user), door_in_app: "always").exists?
  end

  # The next show at an "always" organization, for the menu to name when
  # nothing's on.
  def self.next_listing(user, at: Time.current)
    organization_ids = TicketingProfile.where(organization: TicketingDoorAccess.organizations_for(user), door_in_app: "always")
                                       .pluck(:organization_id)
    listings(organization_ids).where("shows.date_and_time >= ?", at).first
  end

  # The listings in scope (joined to their shows) whose show is still on:
  # today's, and last night's until its door closes. Lists of tonight's and
  # upcoming shows (the Door's, Ticketing's) go by this, so a late show
  # doesn't drop off at midnight while people are still buying at the door
  # (Tim, 2026-10-15: until it ends, or 2 AM when nobody knows the end).
  def self.still_on(scope, at: Time.current)
    late = scope.where(shows: { date_and_time: (at - 1.day)...at.beginning_of_day })
                .includes(show: :space_rental).select { |listing| closes(listing.show) > at }.map(&:id)
    scope.where("shows.date_and_time >= ? OR ticket_listings.id IN (?)", at.beginning_of_day, late.presence || [ 0 ])
  end

  # Where a show stands for the door (Tim, 2026-10-16), so pages lead with
  # the Door when it matters instead of a sales page that has closed:
  #   :before   the door hasn't opened yet
  #   :presale  the door is open and online sales are still on (show day,
  #             before they close)
  #   :door     the door is open and online sales are over: people arriving
  #             now buy at the door
  #   :after    the door has closed
  # nil for a listing that isn't live (a draft, canceled, or its show
  # canceled).
  def self.phase(listing, at: Time.current)
    show = listing.show
    return nil if show.nil? || show.canceled || listing.status.in?(%w[draft canceled])

    window = window(show, listing.organization&.ticketing_profile)
    return :before if at < window.begin
    return :after if at > window.end

    listing.selling?(at) ? :presale : :door
  end

  # Whether people are arriving for this show now (see ARRIVING_BEFORE).
  def self.arriving?(listing, at: Time.current)
    starts = listing.show.date_and_time
    ((starts - ARRIVING_BEFORE)..(starts + ARRIVING_AFTER)).cover?(at)
  end

  def self.door_open?(listing, at: Time.current)
    phase(listing, at: at).in?(%i[presale door])
  end

  def self.window(show, profile = nil)
    starts = show.date_and_time
    opens = if profile&.door_hours_before
      starts - profile.door_hours_before.hours
    else
      [ starts.beginning_of_day, starts - 12.hours ].min
    end
    opens..closes(show)
  end

  # When tonight is over for the door's list: 6 AM tomorrow (a 1 AM show is
  # still tonight's).
  def self.night_ends(at = Time.current)
    (at - NIGHT_ROLLOVER.hours).to_date.next_day.in_time_zone.change(hour: NIGHT_ROLLOVER)
  end

  def self.closes(show)
    starts = show.date_and_time
    return show.ends_at + AFTER_END if show.duration_minutes.present? || show.space_rental.present?

    night = (starts - NIGHT_ROLLOVER.hours).to_date
    [ (night + 1).in_time_zone.change(hour: ENDS_LATE), starts + 4.hours ].max
  end

  def self.listings(organization_ids)
    return TicketListing.none if organization_ids.empty?

    TicketListing.where(organization_id: organization_ids).where.not(status: %w[draft canceled])
                 .joins(:show).where(shows: { canceled: false })
                 .includes(:production, show: :space_rental)
                 .order("shows.date_and_time")
  end
end
