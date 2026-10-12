# frozen_string_literal: true

# The shows someone could be working the door for right now: the app's menu
# offers the Door only then (Tim, 2026-10-13), instead of as a tile every day.
#
# A show's door is open from the morning of the show (or 12 hours before, for
# a show after midnight) until an hour after it ends. A show with no end time
# set stays open until 2 AM the night of the show, since nobody can say when
# it's done.
module DoorTonight
  ENDS_LATE = 2 # o'clock, the morning after a show with no end time
  AFTER_END = 1.hour
  # Before this hour, a show belongs to the night before (a 1 AM show is Friday night's).
  NIGHT_ROLLOVER = 6

  def self.listings_for(user, at: Time.current)
    organizations = TicketingDoorAccess.organizations_for(user)
    return [] if organizations.blank?

    TicketListing.where(organization: organizations).where.not(status: %w[draft canceled])
                 .joins(:show).where(shows: { canceled: false })
                 .where(shows: { date_and_time: (at - 1.day)..(at + 1.day) })
                 .includes(:production, show: :space_rental)
                 .order("shows.date_and_time").to_a
                 .select { |listing| window(listing.show).cover?(at) }
  end

  def self.window(show)
    starts = show.date_and_time
    opens = [ starts.beginning_of_day, starts - 12.hours ].min
    opens..closes(show)
  end

  def self.closes(show)
    starts = show.date_and_time
    return show.ends_at + AFTER_END if show.duration_minutes.present? || show.space_rental.present?

    night = (starts - NIGHT_ROLLOVER.hours).to_date
    [ (night + 1).in_time_zone.change(hour: ENDS_LATE), starts + 4.hours ].max
  end
end
