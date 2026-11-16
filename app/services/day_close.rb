# frozen_string_literal: true

# When a smart day closes (Books V1.3 plan §9.6): when its last show's door
# closes, by the box office's own rule (Ticketing settings → Door, "On show
# days"; DoorTonight.closes: an hour after the show ends; with no end time,
# 4 hours after a daytime show starts or 2 AM after an evening one), and by
# the morning hour at the latest. Tim, 2026-11-16: Settle up said every day
# ran to 6 AM, when the box office already says when a night is over. A day
# with no show runs to the morning hour. Which day a time belongs to doesn't
# change: anything before the morning hour is the night before's.
#
# Only the current day can still be going (any earlier one is past its
# morning hour), so this runs for one day at a time, remembered for the rest
# of the request (Current.day_closes).
module DayClose
  def self.ends_at(organization, date)
    window = SettlementDay.window(organization, date)
    return window.end if organization.settlement_day_mode == "calendar"

    store = (Current.day_closes ||= {})
    store[[ organization.id, date ]] ||= begin
      shows = Show.joins(:production).where(productions: { organization_id: organization.id }, canceled: false, date_and_time: window)
                  .includes(:space_rental).to_a
      closes = shows.map { |show| DoorTonight.closes(show) }.max
      closes ? [ closes, window.end ].min : window.end
    end
  end

  # For the screens: "2 AM", or "6 PM Monday" when it isn't that night.
  def self.words(time, date)
    local = time.in_time_zone
    clock = local.strftime(local.min.zero? ? "%-l %p" : "%-l:%M %p")
    tonight = local.to_date == date || (local.to_date == date + 1 && local.hour < 12)
    tonight ? clock : "#{clock} #{local.strftime('%A')}"
  end
end
