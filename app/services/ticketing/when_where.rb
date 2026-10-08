# frozen_string_literal: true

module Ticketing
  # Everything someone needs to turn up for a show or a class: the time, the
  # place, directions, who can come, the notes. Rendered as its own block under an email's
  # words (shared/mailer/_when_where).
  module WhenWhere
    def self.for(show, door_note: nil, notes: nil, ages: nil)
      location = show.location
      address = [ location&.address1, [ location&.city, location&.state ].compact_blank.join(", "), location&.postal_code ].compact_blank.join(", ")
      {
        date: show.date_and_time.strftime("%A, %B %-d"),
        time: show.date_and_time.strftime("%-l:%M %p"),
        venue: location&.name,
        room: (show.location_space&.name if show.location_space&.name != location&.name),
        address: address.presence,
        online: show.is_online,
        directions_url: address.present? ? "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode([ location.name, address ].join(', '))}" : nil,
        ages: ages.presence,
        door_note: door_note.presence,
        notes: notes.presence
      }
    end
  end
end
