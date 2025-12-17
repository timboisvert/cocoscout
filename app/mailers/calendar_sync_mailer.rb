# frozen_string_literal: true

class CalendarSyncMailer < ApplicationMailer
  def event_invitation(person, show, action_type = "REQUEST")
    @person = person
    @show = show
    @production = show.production
    @action_type = action_type # REQUEST, UPDATE, or CANCEL

    # Generate iCal content
    ical_content = generate_ical(show, person, action_type)

    attachments["event.ics"] = {
      mime_type: "text/calendar",
      content: ical_content
    }

    mail(
      to: person.email,
      subject: "[#{@production.name}] #{action_type == 'CANCEL' ? 'Cancelled: ' : ''}#{@show.secondary_name || @show.event_type.titleize}",
      content_type: "multipart/mixed"
    )
  end

  private

  def generate_ical(show, person, action_type)
    # Simple iCal format
    # In a production system, you might want to use the 'icalendar' gem
    uid = "show-#{show.id}@cocoscout.com"
    timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    start_time = show.date_and_time.utc.strftime("%Y%m%dT%H%M%SZ")
    
    # Estimate end time (add 2 hours for shows, 1 hour for rehearsals/meetings)
    duration_hours = show.event_type == "show" ? 2 : 1
    end_time = (show.date_and_time + duration_hours.hours).utc.strftime("%Y%m%dT%H%M%SZ")

    summary = if show.secondary_name.present?
                "#{show.production.name}: #{show.secondary_name}"
              else
                "#{show.production.name} - #{show.event_type.titleize}"
              end

    location = show.location&.name || ""
    description = "#{show.event_type.titleize} for #{show.production.name}"

    <<~ICAL
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//CocoScout//Calendar Sync//EN
      METHOD:#{action_type}
      BEGIN:VEVENT
      UID:#{uid}
      DTSTAMP:#{timestamp}
      DTSTART:#{start_time}
      DTEND:#{end_time}
      SUMMARY:#{summary}
      LOCATION:#{location}
      DESCRIPTION:#{description}
      STATUS:#{action_type == 'CANCEL' ? 'CANCELLED' : 'CONFIRMED'}
      SEQUENCE:#{show.updated_at.to_i}
      END:VEVENT
      END:VCALENDAR
    ICAL
  end
end
