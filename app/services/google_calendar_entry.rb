# frozen_string_literal: true

# What one show or rental looks like on the organization's Google Calendar:
# the title in the organization's own hand ("Rising Stars · Mainstage · call
# 6:30, show 7:30"), the block, the room's color, and a description that says
# CocoScout manages it and links back. No counts and no money: anyone the
# calendar is shared with reads this.
class GoogleCalendarEntry
  include Rails.application.routes.url_helpers

  MANAGED = "This calendar entry is managed by CocoScout. To change or cancel this date, open it in CocoScout."

  attr_reader :integration, :record

  def initialize(integration, record)
    @integration = integration
    @record = record
  end

  # Links in the description go where the app's emails do.
  def default_url_options = Rails.application.config.action_mailer.default_url_options || {}

  def key = "#{record.class.name}-#{record.id}"

  # The event's id in Google, chosen here (Google takes a to v and digits), so
  # writing the same date twice can never leave two events.
  def event_id = "#{show? ? 'cocoevent' : 'cocorental'}#{record.id}"

  # The event resource Google is sent. status: "confirmed" brings back an
  # event someone deleted in Google.
  def payload
    {
      summary: title,
      location: place,
      description: description,
      start: { dateTime: starts_at.iso8601, timeZone: zone_name },
      end: { dateTime: ends_at.iso8601, timeZone: zone_name },
      colorId: integration.room_color(room),
      status: "confirmed",
      source: { title: "CocoScout", url: manage_url },
      extendedProperties: { private: { cocoscout: key } }
    }.compact
  end

  def digest = Digest::SHA256.hexdigest(payload.to_json)

  def title
    parts = [ name ]
    parts << room.name if room && integration.calendar_title_part?("room")
    parts << times_in_title if times_in_title
    parts.join(" · ")
  end

  def room = record.location_space

  # The block opens at the earliest of: the show's own time, its call time
  # (when the organization starts blocks there), and the start of the rental
  # it sits in (when it blocks the whole rental).
  def starts_at
    return record.starts_at.in_time_zone(zone) unless show?

    times = [ record.date_and_time ]
    times << call_time if call_time && integration.calendar_title_part?("start_at_call")
    times << rental.starts_at if rental
    times.min.in_time_zone(zone)
  end

  def ends_at
    finish = [ record.ends_at, rental&.ends_at ].compact.max
    [ finish, starts_at + 15.minutes ].max.in_time_zone(zone)
  end

  private

  def show? = record.is_a?(Show)
  def organization = integration.organization
  def zone = ActiveSupport::TimeZone[organization.time_zone.presence || TimeZones.default] || Time.zone
  def zone_name = zone.tzinfo.name
  def clock(time) = time.in_time_zone(zone).strftime("%-l:%M")
  def clock_long(time) = time.in_time_zone(zone).strftime("%-l:%M %P")

  # The show's own name: the production's for a plain show ("Rising Stars",
  # not "Rising Stars Show"), the event's for everything else ("Rising Stars
  # Rehearsal", or what someone named it).
  def name
    return "Rental: #{record.contract.contractor_name}" unless show?

    production = record.production.name
    custom = record.name_subtitle
    return record.event_type == "show" ? production : record.display_name if custom.blank?

    custom.downcase.include?(production.downcase) ? custom : "#{production}: #{custom}"
  end

  def call_time
    record.call_time if show? && record.call_time_enabled && record.call_time.present? && record.call_time < record.date_and_time
  end

  # The rental this show blocks out: the one it sits in, when its contract
  # is live, it is the rental's only date, and the organization blocks the
  # whole rental time. Otherwise nil, and the show keeps its own times.
  def rental
    return @rental if defined?(@rental)

    rental = show? ? record.space_rental : nil
    contract = rental&.contract
    whole = rental && contract && (contract.status_active? || contract.status_completed?) &&
            integration.calendar_title_part?("rental_block") && rental.shows.where(canceled: false).count == 1
    @rental = whole ? rental : nil
  end

  def start_word = record.event_type == "show" ? "show" : "start"

  # "call 6:30, show 7:30", or just "show 8:00" when the block opens before
  # the show for the rental.
  def times_in_title
    return nil unless show? && integration.calendar_title_part?("call_time")
    return "call #{clock(call_time)}, #{start_word} #{clock(record.date_and_time)}" if call_time

    "#{start_word} #{clock(record.date_and_time)}" if starts_at < record.date_and_time
  end

  def place
    location = record.location
    return (show? && record.respond_to?(:is_online) && record.is_online ? "Online" : nil) unless location

    [ room&.name, location.full_address ].compact.join(", ")
  end

  def manage_url
    show? ? manage_show_url(record.production, record) : manage_contract_url(record.contract)
  end

  def link(text, url) = %(<a href="#{ERB::Util.html_escape(url)}">#{ERB::Util.html_escape(text)}</a>)

  def description
    lines = [ "<b>#{MANAGED}</b>", link(show? ? "Manage this event in CocoScout" : "Open the contract in CocoScout", manage_url), "" ]
    lines.concat(show? ? show_lines : rental_lines)
    lines.join("<br>")
  end

  def show_lines
    lines = []
    times = [ "#{start_word.capitalize} time #{clock_long(record.date_and_time)}" ]
    times.unshift("Call time #{clock_long(call_time)}") if call_time
    lines << times.join(" · ")
    team = record.production.production_permissions.includes(user: :default_person).filter_map { |p| p.user.person&.name }.sort
    lines << "Production team: #{ERB::Util.html_escape(team.to_sentence)}" if team.any?
    if (url = ticket_url)
      lines << link("Ticket page", url)
    end
    lines.concat(contract_lines)
  end

  # A date under contract: who with, the time they have the room, the contract.
  def contract_lines
    contract = record.space_rental&.contract
    return [] unless contract && (contract.status_active? || contract.status_completed?)

    held = record.space_rental
    [ "Under contract with #{ERB::Util.html_escape(contract.contractor_name)}",
      "Rental #{clock_long(held.starts_at)} to #{clock_long(held.ends_at)}",
      link("Open the contract in CocoScout", manage_contract_url(contract)) ]
  end

  def rental_lines
    contract = record.contract
    lines = [ "Under contract with #{ERB::Util.html_escape(contract.contractor_name)}" ]
    if record.has_separate_event_time?
      lines << "Event #{clock_long(record.effective_event_starts_at)} to #{clock_long(record.effective_event_ends_at)}"
    end
    lines
  end

  # The date's ticket page, while it's on sale.
  def ticket_url
    listing = record.ticket_listing
    profile = organization.ticketing_profile
    return nil unless listing && profile&.enabled? && listing.status == "on_sale"

    tickets_event_url(org: profile.slug, event: listing.slug)
  end
end
