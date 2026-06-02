# frozen_string_literal: true

# Builds RFC 5545 calendar feeds for the Open Mic Finder. Uses the
# `icalendar` gem already in the Gemfile.
class MicIcsBuilder
  def self.for_mic(mic, occurrences:)
    cal = Icalendar::Calendar.new
    cal.append_custom_property("X-WR-CALNAME", mic.name)
    cal.append_custom_property("X-WR-TIMEZONE", mic.venue.timezone || "America/Chicago")

    occurrences.each do |occ|
      cal.event do |e|
        e.uid          = "mic-#{mic.id}-#{occ[:starts_at].to_i}@cocoscout.com"
        e.summary      = mic.name
        e.description  = mic.blurb.to_s
        e.location     = mic.venue.full_address
        e.dtstart      = Icalendar::Values::DateTime.new(occ[:starts_at])
        spot_min = spot_length_int(mic.spot_length_minutes)
        if spot_min
          e.dtend = Icalendar::Values::DateTime.new(occ[:starts_at] + (spot_min * 60))
        end
        if occ[:mic_status] == "cancelled"
          e.status = "CANCELLED"
        end
      end
    end

    cal.publish
    cal.to_ical
  end

  def self.for_city(city, state, mics:)
    cal = Icalendar::Calendar.new
    cal.append_custom_property("X-WR-CALNAME", "Open mics in #{city}, #{state}")

    mics.each do |mic|
      mic.next_occurrences(limit: 8).each do |occ|
        cal.event do |e|
          e.uid          = "mic-#{mic.id}-#{occ[:starts_at].to_i}@cocoscout.com"
          e.summary      = "#{mic.name} · #{mic.venue.name}"
          e.description  = mic.blurb.to_s
          e.location     = mic.venue.full_address
          e.dtstart      = Icalendar::Values::DateTime.new(occ[:starts_at])
          spot_min = spot_length_int(mic.spot_length_minutes)
          if spot_min
            e.dtend = Icalendar::Values::DateTime.new(occ[:starts_at] + (spot_min * 60))
          end
          e.status = "CANCELLED" if occ[:mic_status] == "cancelled"
        end
      end
    end

    cal.publish
    cal.to_ical
  end

  # spot_length_minutes is free-text ("5", "3-5 minutes"). For the iCal
  # dtend we just need the leading digit run; if there isn't one, leave
  # dtend unset and let clients render the event as a point in time.
  def self.spot_length_int(value)
    n = value.to_s.scan(/\d+/).first
    n&.to_i
  end
  private_class_method :spot_length_int
end
