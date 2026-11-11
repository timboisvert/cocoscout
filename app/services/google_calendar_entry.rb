# frozen_string_literal: true

# What one show or rental looks like on the organization's Google Calendar:
# the title in the organization's own hand ("Rising Stars · Mainstage · call
# 6:30, show 7:30"), the block, the room's color, and a description that says
# CocoScout manages it and links back. No counts and no money: anyone the
# calendar is shared with reads this.
class GoogleCalendarEntry
  include Rails.application.routes.url_helpers

  MANAGED = "Managed by CocoScout. Changes made here are undone. To move or remove this date, open it in CocoScout."

  attr_reader :integration, :record

  def initialize(integration, record)
    @integration = integration
    @record = record
  end

  # Links in the description go where the app's emails do.
  def default_url_options = Rails.application.config.action_mailer.default_url_options || {}

  def key = "#{record.class.name}-#{record.id}"

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
    parts << times_in_title if show? && times_in_title
    parts.join(" · ")
  end

  def room = record.location_space

  def starts_at
    start = show? && call_time && integration.calendar_title_part?("start_at_call") ? call_time : (show? ? record.date_and_time : record.starts_at)
    start.in_time_zone(zone)
  end

  def ends_at
    finish = show? ? record.ends_at : record.ends_at
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

  def start_word = record.event_type == "show" ? "show" : "start"

  def times_in_title
    return nil unless call_time && integration.calendar_title_part?("call_time")

    "call #{clock(call_time)}, #{start_word} #{clock(record.date_and_time)}"
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
    lines = [ "<b>#{MANAGED}</b>", link(show? ? "Manage this date in CocoScout" : "Open the contract in CocoScout", manage_url), "" ]
    lines.concat(show? ? show_lines : rental_lines)
    lines.join("<br>")
  end

  def show_lines
    lines = []
    times = [ "#{start_word.capitalize} #{clock_long(record.date_and_time)}" ]
    times << "call #{clock_long(call_time)}" if call_time
    lines << times.join(" · ")
    team = record.production.production_permissions.includes(user: :default_person).filter_map { |p| p.user.person&.name }.sort
    lines << "Production team: #{ERB::Util.html_escape(team.to_sentence)}" if team.any?
    if (url = ticket_url)
      lines << link("Ticket page", url)
    end
    lines
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
