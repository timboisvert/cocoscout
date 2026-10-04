# frozen_string_literal: true

module Ticketing
  # "Add to calendar": one .ics file with an event per date (a show, or every
  # session of a course). events: [{ uid:, starts:, ends:, summary:,
  # location:, description: }].
  module Calendar
    def self.ics(events)
      stamp = ->(time) { time.utc.strftime("%Y%m%dT%H%M%SZ") }
      escape = ->(text) { text.to_s.gsub(/[\;,]/) { |c| "\\#{c}" }.gsub("\n", "\\n") }
      lines = [ "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CocoScout//Tickets//EN" ]
      events.each do |event|
        lines.concat([
          "BEGIN:VEVENT", "UID:#{event[:uid]}", "DTSTAMP:#{stamp.call(Time.current)}",
          "DTSTART:#{stamp.call(event[:starts])}", "DTEND:#{stamp.call(event[:ends])}",
          "SUMMARY:#{escape.call(event[:summary])}", "LOCATION:#{escape.call(event[:location])}",
          "DESCRIPTION:#{escape.call(event[:description])}", "END:VEVENT"
        ])
      end
      (lines << "END:VCALENDAR").join("\r\n")
    end

    # Where a show is, the way a calendar wants it.
    def self.place(show)
      [ show.location&.name, show.location&.address1, show.location&.city ].compact_blank.join(", ")
    end
  end
end
