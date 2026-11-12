# frozen_string_literal: true

# Keeps an organization's Google Calendar as CocoScout says it is (Tim,
# 2026-11-11). One direction: CocoScout writes, Google shows.
#
#   - a show or rental changes  → that one event is written again
#
# A date is one event (Tim, 2026-11-11). A contract makes shows, so a date
# under contract is its show, blocked for the whole rental if the
# organization wants that; the rental never goes on beside it. Only a rental
# with no show of its own is written as a block in its own right.
#   - a show is canceled, deleted, or a contract is cancelled → its event goes
#   - every night               → every coming event is written again, so
#     anything edited or deleted in Google is put back, and any event of ours
#     that no longer stands for anything is taken off
#
# Only from now on (Tim, 2026-11-11): a date that has already happened is
# never written, written again, or taken off. Whatever the calendar says
# about the past stays as it is.
#
# A date that hasn't changed costs no call: each event's digest is kept.
class GoogleCalendarSync
  # Google refuses a burst of writes to one calendar ("Rate Limit Exceeded"),
  # so a full pass leaves a beat between events, and a refused call waits
  # longer each time before it is tried again.
  PACE = 0.25
  BACK_OFF = [ 2, 4, 8, 16, 32 ].freeze

  attr_reader :integration

  def self.for(organization_id)
    integration = Integration.google_calendar.where(status: %w[connected error]).find_by(organization_id: organization_id)
    new(integration) if integration&.calendar_id && integration.refresh_token.present?
  end

  # Whether an organization has a calendar to keep, cheaply, for callbacks.
  def self.on_for?(organization_id)
    organization_id.present? && Integration.google_calendar.where(status: %w[connected error]).exists?(organization_id: organization_id)
  end

  def initialize(integration)
    @integration = integration
  end

  # On connecting: the calendar CocoScout made the last time, if this Google
  # account still has it, or else a new one. Every connect used to make a new
  # one, and the old one stayed in the account under the same name with dates
  # nothing would ever change again (Tim, 2026-11-12). :kept or :made.
  def take_calendar!(previous_id)
    calendar = previous_id && earlier_calendar(previous_id)
    unless calendar
      create_calendar!
      return :made
    end

    integration.update!(settings: integration.settings.merge("calendar_id" => calendar["id"], "calendar_name" => calendar["summary"]))
    :kept
  end

  # The calendar CocoScout makes on connecting. Development's says so, so a
  # test connection is never taken for the organization's real one.
  def create_calendar!
    organization = integration.organization
    zone = ActiveSupport::TimeZone[organization.time_zone.presence || TimeZones.default] || Time.zone
    name = "#{organization.name} (CocoScout#{' dev' if Rails.env.development?})"
    calendar = api.create_calendar(summary: name, time_zone: zone.tzinfo.name,
                                   description: "Kept by CocoScout. To change a date, change it in CocoScout.")
    integration.update!(settings: integration.settings.merge("calendar_id" => calendar["id"], "calendar_name" => name))
  end

  # Everything, written or removed as needed. force: write every coming
  # event again whether or not CocoScout thinks it changed (the nightly pass).
  def sync_all!(force: false)
    rows = integration.calendar_sync_events.index_by { |row| [ row.syncable_type, row.syncable_id ] }
    wanted = wanted_records.index_by { |record| [ record.class.name, record.id ] }

    wanted.each do |key, record|
      pause(PACE) if write(GoogleCalendarEntry.new(integration, record), rows[key], force: force)
    end
    (rows.keys - wanted.keys).each do |key|
      record = rows[key].syncable
      next if record && (over?(record) || belongs_on_calendar?(record))

      remove(rows[key])
      pause(PACE)
    end
    sweep_strays!(wanted.values)
    integration.record_success!
  rescue GoogleCalendarApi::Unauthorized
    integration.record_error!("Google no longer lets CocoScout in. Connect Google Calendar again.")
  rescue GoogleCalendarApi::NotFound
    integration.record_error!("The calendar CocoScout made is gone from Google. Disconnect, then connect again to make a new one.")
  rescue GoogleCalendarApi::RateLimited
    integration.record_error!("Google asked CocoScout to slow down. The rest of your dates will be added in a few minutes.")
    raise
  rescue GoogleCalendarApi::Error => e
    integration.record_error!(e.message)
    raise
  end

  # One show or rental, by name and id (it may already be deleted).
  def sync_record!(type, id)
    return unless CalendarSyncEvent::SYNCABLES.include?(type)

    record = type.constantize.find_by(id: id)
    return if record && over?(record)

    row = integration.calendar_sync_events.find_by(syncable_type: type, syncable_id: id)
    if record && belongs_on_calendar?(record)
      write(GoogleCalendarEntry.new(integration, record), row)
    elsif row
      remove(row)
    end
    # A rental's times are its shows' blocks.
    Show.where(space_rental_id: id).ids.each { |show_id| sync_record!("Show", show_id) } if type == "SpaceRental"
  rescue GoogleCalendarApi::Unauthorized
    integration.record_error!("Google no longer lets CocoScout in. Connect Google Calendar again.")
  end

  # Whether a show or rental has a place on this organization's calendar at
  # all, whenever it is.
  def belongs_on_calendar?(record)
    case record
    when Show
      production = record.production
      integration.calendar_event_type?(record.event_type) && !record.canceled && record.date_and_time.present? &&
        production.present? && production.organization_id == integration.organization_id &&
        production.production_type != "course" && !production.archived?
    when SpaceRental
      contract = record.contract
      contract.present? && contract.organization_id == integration.organization_id &&
        (contract.status_active? || contract.status_completed?) && record.shows.none?
    else
      false
    end
  end

  # Already happened: a show that has started, a rental that has ended.
  def over?(record)
    time = record.is_a?(Show) ? record.date_and_time : record.ends_at
    time.present? && time < Time.current
  end

  private

  # What a full pass writes: everything from now on.
  def wanted_records
    from = Time.current
    organization = integration.organization
    shows = Show.where(production: organization.productions.schedulable.active, canceled: false)
                .where(event_type: integration.calendar_event_types, date_and_time: from..)
                .includes(:location, :location_space, :ticket_listing, production: :organization, space_rental: :contract).to_a
    # A rental nobody has put a show in still holds its room.
    rentals = SpaceRental.joins(:contract).where(contracts: { organization_id: organization.id, status: %w[active completed] })
                         .where(ends_at: from..).where.missing(:shows).includes(:location, :location_space, :contract).to_a
    shows + rentals
  end

  # Our own events on Google that nothing in CocoScout stands behind any
  # more: written before a disconnect (which forgets every row), or on this
  # calendar when it was kept from an earlier connection. Without this they
  # stay forever. Only CocoScout's ids, and only dates that haven't started.
  def sweep_strays!(records)
    keep = records.map { |record| GoogleCalendarEntry.new(integration, record).event_id }.to_set
    keep.merge(integration.calendar_sync_events.pluck(:external_id))
    page = nil
    loop do
      body = patiently { api.list_events(integration.calendar_id, time_min: Time.current, page_token: page) }
      Array(body["items"]).each do |event|
        id = event["id"].to_s
        next unless id.start_with?("cocoevent", "cocorental") && !keep.include?(id) && event["status"] != "cancelled"
        next unless (starts = event.dig("start", "dateTime")) && Time.zone.parse(starts) > Time.current

        patiently { api.delete_event(integration.calendar_id, id) }
        pause(PACE)
      end
      break if (page = body["nextPageToken"].presence).nil?
    end
  end

  # The earlier calendar, if Google still lets this account at it: another
  # account, or a calendar deleted since, is no calendar.
  def earlier_calendar(id)
    calendar = api.get_calendar(id)
    calendar if calendar["id"].present?
  rescue GoogleCalendarApi::RateLimited
    raise
  rescue GoogleCalendarApi::Error
    nil
  end

  # Whether Google was called.
  def write(entry, row, force: false)
    digest = entry.digest
    return false if row && row.digest == digest && !force

    event = patiently { row ? update_or_insert(row, entry) : insert(entry) }
    row ||= integration.calendar_sync_events.new(syncable_type: entry.record.class.name, syncable_id: entry.record.id)
    row.update!(external_id: event["id"], digest: digest, synced_at: Time.current)
    true
  end

  # The event goes in under an id of our choosing. If Google already has that
  # id (an earlier pass wrote it and never got to note it), it's written over.
  def insert(entry)
    api.insert_event(integration.calendar_id, entry.payload.merge(id: entry.event_id))
  rescue GoogleCalendarApi::Conflict
    api.update_event(integration.calendar_id, entry.event_id, entry.payload)
  end

  # The event may have been purged from Google entirely: then it's made anew.
  def update_or_insert(row, entry)
    api.update_event(integration.calendar_id, row.external_id, entry.payload)
  rescue GoogleCalendarApi::NotFound
    insert(entry)
  end

  def remove(row)
    patiently { api.delete_event(integration.calendar_id, row.external_id) }
    row.destroy!
  end

  # Google said slow down: wait, longer each time, then give up to the job's
  # own retry, which picks up where this pass stopped.
  def patiently
    waits = BACK_OFF.dup
    begin
      yield
    rescue GoogleCalendarApi::RateLimited
      raise if waits.empty?

      pause(waits.shift)
      retry
    end
  end

  def pause(seconds) = sleep(seconds)

  # Google's access tokens last an hour: a fresh one when this one is nearly
  # spent, kept for the next job.
  def api
    if integration.token_expires_at.nil? || integration.token_expires_at < 2.minutes.from_now
      fresh = GoogleCalendarApi.refresh(integration.refresh_token)
      integration.update!(tokens: integration.tokens.merge(fresh))
      @api = nil
    end
    @api ||= GoogleCalendarApi.new(integration.access_token)
  end
end
