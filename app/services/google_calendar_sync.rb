# frozen_string_literal: true

# Keeps an organization's Google Calendar as CocoScout says it is (Tim,
# 2026-11-11). One direction: CocoScout writes, Google shows.
#
#   - a show or rental changes  → that one event is written again
#   - a show is canceled, deleted, or a contract is cancelled → its event goes
#   - every night               → every coming event is written again, so
#     anything edited or deleted in Google is put back
#
# A date that hasn't changed costs no call: each event's digest is kept.
class GoogleCalendarSync
  # How far back a full pass reaches. Older events stay on the calendar as
  # they were; they're just not rewritten.
  LOOK_BACK = 31.days

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

    wanted.each { |key, record| write(GoogleCalendarEntry.new(integration, record), rows[key], force: force) }
    (rows.keys - wanted.keys).each do |key|
      record = rows[key].syncable
      remove(rows[key]) unless record && belongs_on_calendar?(record)
    end
    integration.record_success!
  rescue GoogleCalendarApi::Unauthorized
    integration.record_error!("Google no longer lets CocoScout in. Connect Google Calendar again.")
  rescue GoogleCalendarApi::NotFound
    integration.record_error!("The calendar CocoScout made is gone from Google. Disconnect, then connect again to make a new one.")
  rescue GoogleCalendarApi::Error => e
    integration.record_error!(e.message)
    raise
  end

  # One show or rental, by name and id (it may already be deleted).
  def sync_record!(type, id)
    return unless CalendarSyncEvent::SYNCABLES.include?(type)

    record = type.constantize.find_by(id: id)
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

  private

  # What a full pass writes: everything from a month back onward.
  def wanted_records
    from = LOOK_BACK.ago
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

  def write(entry, row, force: false)
    digest = entry.digest
    return if row && row.digest == digest && !force

    event = row ? update_or_insert(row, entry) : api.insert_event(integration.calendar_id, entry.payload)
    row ||= integration.calendar_sync_events.new(syncable_type: entry.record.class.name, syncable_id: entry.record.id)
    row.update!(external_id: event["id"], digest: digest, synced_at: Time.current)
  end

  # The event may have been purged from Google entirely: then it's made anew.
  def update_or_insert(row, entry)
    api.update_event(integration.calendar_id, row.external_id, entry.payload)
  rescue GoogleCalendarApi::NotFound
    api.insert_event(integration.calendar_id, entry.payload)
  end

  def remove(row)
    api.delete_event(integration.calendar_id, row.external_id)
    row.destroy!
  end

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
