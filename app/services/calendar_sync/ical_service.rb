# frozen_string_literal: true

module CalendarSync
  class IcalService < BaseService
    # iCal doesn't need create/update/delete since it's a pull-based feed
    # The feed is generated on-demand when requested

    def create_event(show)
      # No-op for iCal - events are generated dynamically
    end

    def update_event(calendar_event)
      # No-op for iCal - events are generated dynamically
    end

    def delete_event(calendar_event)
      # No-op for iCal - events are generated dynamically
    end

    def sync_all
      # For iCal, we just mark as synced since there's nothing to push
      subscription.mark_synced!
    end

    # Generate the iCal feed content
    def generate_feed
      shows = subscription.shows_to_sync

      calendar = Icalendar::Calendar.new

      calendar.prodid = "-//CocoScout//Calendar Feed//EN"
      calendar.version = "2.0"
      calendar.x_wr_calname = "CocoScout Shows & Events"

      shows.find_each do |show|
        event = Icalendar::Event.new
        event.dtstart = Icalendar::Values::DateTime.new(event_start_time(show), tzid: Time.zone.name)
        event.dtend = Icalendar::Values::DateTime.new(event_end_time(show), tzid: Time.zone.name)
        event.summary = event_title(show)
        event.description = event_description(show)
        event.location = event_location(show)
        event.uid = "show-#{show.id}@cocoscout.com"
        event.sequence = show.updated_at.to_i
        event.status = show.canceled? ? "CANCELLED" : "CONFIRMED"

        calendar.add_event(event)
      end

      calendar.to_ical
    end
  end
end
