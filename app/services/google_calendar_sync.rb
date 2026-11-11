# frozen_string_literal: true

# Keeps an organization's Google Calendar as CocoScout says it is (Tim,
# 2026-11-11). One direction: CocoScout writes, Google shows.
#
#   - a show or rental changes  → that one event is written again
#   - a show is canceled, deleted, or a contract is cancelled → its event goes
#   - every night               → every coming event is written again, so
#     anything edited or deleted in Google is put back
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

  # The calendar CocoScout makes on connecting.
  def create_calendar!
    organization = integration.organization
    zone = ActiveSupport::TimeZone[organization.time_zone.presence || TimeZones.default] || Time.zone
    name = "#{organization.name} (CocoScout)"
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
  rescue GoogleCalendarApi::Unauthorized
    integration.record_error!("Google no longer lets CocoScout in. Connect Google Calendar again.")
  end

  # Whether a show or rental has a place on this organization's calendar at
  # all, whenever it is.
  def belongs_on_calendar?(record)
    case record
    when Show
      production = record.production
      integration.calendar_includes?("shows") && !record.canceled && record.date_and_time.present? &&
        production.present? && production.organization_id == integration.organization_id &&
        production.production_type != "course" && !production.archived?
    when SpaceRental
      contract = record.contract
      integration.calendar_includes?("rentals") && contract.present? &&
        contract.organization_id == integration.organization_id && (contract.status_active? || contract.status_completed?)
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
    records = []
    if integration.calendar_includes?("shows")
      records.concat(Show.where(production: organization.productions.schedulable.active, canceled: false)
                         .where(date_and_time: from..)
                         .includes(:location, :location_space, :ticket_listing, production: :organization).to_a)
    end
    if integration.calendar_includes?("rentals")
      records.concat(SpaceRental.joins(:contract).where(contracts: { organization_id: organization.id, status: %w[active completed] })
                                .where(ends_at: from..).includes(:location, :location_space, :contract).to_a)
    end
    records
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
