# frozen_string_literal: true

require "rails_helper"

# The organization's Google Calendar, kept by CocoScout (Tim, 2026-11-11):
# what an event says, which color it takes, and when it's written, written
# again, or taken off. Google itself is a double here.
RSpec.describe GoogleCalendarSync do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters", time_zone: "Central Time (US & Canada)") }
  let(:location) { create(:location, organization: org, name: "Stars & Garters", address1: "3914 N. Clark St.", address2: nil, city: "Chicago", state: "IL", postal_code: "60613") }
  let(:mainstage) { location.location_spaces.create!(name: "Mainstage") }
  let(:ruse) { location.location_spaces.create!(name: "Ruse Room") }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:showtime) { 5.days.from_now.in_time_zone("Central Time (US & Canada)").change(hour: 19, min: 30) }
  let!(:integration) do
    org.integrations.create!(provider: "google_calendar", status: "connected",
                             settings: { "calendar_id" => "cal-1", "calendar_name" => "Stars & Garters (CocoScout)",
                                         "room_colors" => { ruse.id.to_s => "4", mainstage.id.to_s => "7" } },
                             tokens: { "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 50.minutes.from_now.iso8601 })
  end
  let(:api) { instance_double(GoogleCalendarApi) }
  let(:sync) { described_class.new(integration) }

  def show_at(time = showtime, **attrs)
    create(:show, { production: production, date_and_time: time, location: location, location_space: mainstage }.merge(attrs))
  end

  before do
    allow(GoogleCalendarApi).to receive(:new).with("tok").and_return(api)
    next_id = 0
    allow(api).to receive(:insert_event) { { "id" => "g#{next_id += 1}" } }
    allow(api).to receive(:update_event) { |_cal, id, _event| { "id" => id } }
    allow(api).to receive(:delete_event).and_return({})
    allow(api).to receive(:list_events).and_return({ "items" => [] })
    allow_any_instance_of(GoogleCalendarSync).to receive(:pause) { |_sync, seconds| pauses << seconds }
  end
  let(:pauses) { [] }

  describe GoogleCalendarEntry do
    def entry(record) = described_class.new(integration.reload, record)

    it "titles a show the way the organization writes it: name, room, call time, show time" do
      show = show_at(call_time: showtime - 1.hour, call_time_enabled: true)

      expect(entry(show).title).to eq("Rising Stars · Mainstage · call 6:30, show 7:30")
      expect(entry(show).starts_at).to eq(showtime - 1.hour)
      expect(entry(show).payload[:end][:dateTime]).to eq((showtime + 2.hours).iso8601)
      expect(entry(show).payload[:start][:timeZone]).to eq("America/Chicago")
    end

    # A moved or copied show keeps the date its call time was typed on.
    it "reads a call time as a clock on the show's own day, whatever date it carries" do
      show = show_at(call_time: showtime - 3.weeks - 30.minutes, call_time_enabled: true)

      expect(entry(show).starts_at).to eq(showtime - 30.minutes)
      expect(entry(show).ends_at - entry(show).starts_at).to eq(2.hours + 30.minutes)
      expect(entry(show).title).to eq("Rising Stars · Mainstage · call 7:00, show 7:30")
    end

    it "leaves out what the organization switched off" do
      show = show_at(call_time: showtime - 1.hour, call_time_enabled: true)
      integration.update!(settings: integration.settings.merge("title" => { "room" => false, "call_time" => false, "start_at_call" => false }))

      expect(entry(show).title).to eq("Rising Stars")
      expect(entry(show).starts_at).to eq(showtime)
    end

    it "names a rehearsal as one, and a named event by its name" do
      rehearsal = show_at(event_type: "rehearsal")
      named = show_at(showtime + 1.day, secondary_name: "Fall Showcase")

      expect(entry(rehearsal).title).to eq("#{rehearsal.display_name} · Mainstage")
      expect(entry(rehearsal).title).to include("Rehearsal")
      expect(entry(named).title).to eq("Rising Stars: Fall Showcase · Mainstage")
    end

    it "takes the room's color, and the one color for everything else without a room" do
      integration.update!(settings: integration.settings.merge("other_color" => "8"))

      expect(entry(show_at).payload[:colorId]).to eq("7")
      expect(entry(show_at(showtime + 1.day, location_space: ruse)).payload[:colorId]).to eq("4")
      expect(entry(show_at(showtime + 2.days, location_space: nil)).payload[:colorId]).to eq("8")
    end

    it "says CocoScout manages it and links back, with the room and address, and no numbers" do
      ProductionPermission.create!(user: create(:user).tap { |u| create(:person, user: u, name: "Veronica Ortiz").then { |p| u.update!(default_person: p) } },
                                   production: production, role: "manager")
      show = show_at
      payload = entry(show).payload

      expect(payload[:description]).to include("This calendar entry is managed by CocoScout. To change or cancel this date, open it in CocoScout.", "Manage this event in CocoScout", "/manage/shows/#{production.id}/#{show.id}", "Production team: Veronica Ortiz")
      expect(payload[:location]).to eq("Mainstage, Stars & Garters, 3914 N. Clark St., Chicago, IL 60613")
      expect(payload[:extendedProperties]).to eq({ private: { cocoscout: "Show-#{show.id}" } })
      expect(payload[:status]).to eq("confirmed")
    end

    it "gives the call time, then the show time, in the description" do
      with_call = entry(show_at(call_time: showtime - 1.hour, call_time_enabled: true)).payload[:description]
      without = entry(show_at(showtime + 1.day)).payload[:description]

      expect(with_call).to include("Call time 6:30 pm · Show time 7:30 pm")
      expect(without).to include("Show time 7:30 pm")
      expect(without).not_to include("Call time")
    end

    # A contract makes shows: the date is that show, never a second event
    # for the rental (Tim, 2026-11-11).
    it "blocks the whole rental for a show under contract, and says when the show is" do
      contract = create(:contract, :active, organization: org, contractor_name: "Kelty Productions")
      rental = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime - 1.hour, ends_at: showtime + 2.hours, confirmed: true)
      show = show_at(location_space: ruse, space_rental: rental, duration_minutes: 90)

      expect(entry(show).title).to eq("Rising Stars · Ruse Room · show 7:30")
      expect(entry(show).starts_at).to eq(showtime - 1.hour)
      expect(entry(show).ends_at).to eq(showtime + 2.hours)
      expect(entry(show).payload[:description]).to include("Under contract with Kelty Productions", "Rental 6:30 pm to 9:30 pm", "/manage/contracts/#{contract.id}")
    end

    it "keeps the show's own times when the whole-rental block is off, or the contract isn't live" do
      contract = create(:contract, :active, organization: org)
      rental = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime - 1.hour, ends_at: showtime + 2.hours, confirmed: true)
      show = show_at(location_space: ruse, space_rental: rental, duration_minutes: 90)
      integration.update!(settings: integration.settings.merge("title" => { "rental_block" => false }))

      expect(entry(show).starts_at).to eq(showtime)
      expect(entry(show).ends_at).to eq(showtime + 90.minutes)
      expect(entry(show).title).to eq("Rising Stars · Ruse Room")

      integration.update!(settings: integration.settings.merge("title" => {}))
      contract.update_columns(status: "draft")
      expect(entry(show.reload).starts_at).to eq(showtime)
    end

    it "shows a rental with no show of its own for the whole time the renter has the room" do
      contract = create(:contract, :active, organization: org, contractor_name: "Kelty Productions")
      rental = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime - 2.hours, ends_at: showtime + 4.hours, confirmed: true)

      expect(entry(rental).title).to eq("Rental: Kelty Productions · Ruse Room")
      expect(entry(rental).starts_at).to eq(showtime - 2.hours)
      expect(entry(rental).payload[:colorId]).to eq("4")
      expect(entry(rental).payload[:description]).to include("/manage/contracts/#{contract.id}")
    end
  end

  describe "#take_calendar!" do
    it "keeps the calendar from the last connection when this account still has it" do
      allow(api).to receive(:get_calendar).with("cal-old").and_return({ "id" => "cal-old", "summary" => "Stars & Garters (CocoScout)" })
      allow(api).to receive(:create_calendar)

      expect(sync.take_calendar!("cal-old")).to eq(:kept)
      expect(integration.reload.calendar_id).to eq("cal-old")
      expect(api).not_to have_received(:create_calendar)
    end

    it "makes a new one when the old one is gone or in another account" do
      allow(api).to receive(:get_calendar).and_raise(GoogleCalendarApi::NotFound, "Not Found")
      allow(api).to receive(:create_calendar).and_return({ "id" => "cal-new" })

      expect(sync.take_calendar!("cal-old")).to eq(:made)
      expect(integration.reload.calendar_id).to eq("cal-new")
    end

    it "says dev on a calendar made from development" do
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(api).to receive(:create_calendar).and_return({ "id" => "cal-new" })

      sync.take_calendar!(nil)

      expect(api).to have_received(:create_calendar).with(hash_including(summary: "Stars & Garters (CocoScout dev)"))
    end
  end

  describe "#sync_all!" do
    it "puts every coming date on the calendar once: a show under contract is one event, not two" do
      show = show_at
      contract = create(:contract, :active, organization: org)
      rental = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime + 1.day, ends_at: showtime + 1.day + 3.hours, confirmed: true)
      held = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime + 5.days, ends_at: showtime + 5.days + 3.hours, confirmed: true)
      contracted = show_at(showtime + 5.days, location_space: ruse, space_rental: held)
      draft = create(:contract, organization: org)
      draft.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime + 3.days, ends_at: showtime + 3.days + 3.hours)
      show_at(showtime + 2.days, canceled: true)
      create(:show, production: create(:production), date_and_time: showtime) # another organization's

      sync.sync_all!

      expect(api).to have_received(:insert_event).exactly(3).times
      expect(integration.calendar_sync_events.pluck(:syncable_type, :syncable_id)).to contain_exactly([ "Show", show.id ], [ "Show", contracted.id ], [ "SpaceRental", rental.id ])
      expect(integration.reload.last_synced_at).to be_present

      sync.sync_all!
      expect(api).to have_received(:insert_event).exactly(3).times
      expect(api).not_to have_received(:update_event)
    end

    it "writes a date again when it changes, and only that one" do
      show = show_at
      other = show_at(showtime + 1.day)
      sync.sync_all!

      show.update!(date_and_time: showtime + 1.hour)
      described_class.new(integration.reload).sync_all!

      row = integration.calendar_sync_events.find_by(syncable_type: "Show", syncable_id: show.id)
      expect(api).to have_received(:update_event).once.with("cal-1", row.external_id, hash_including(summary: "Rising Stars · Mainstage"))
      expect(integration.calendar_sync_events.find_by(syncable_id: other.id)).to be_present
    end

    it "takes a canceled date off the calendar" do
      show = show_at
      sync.sync_all!
      external_id = integration.calendar_sync_events.sole.external_id

      show.update!(canceled: true)
      described_class.new(integration.reload).sync_all!

      expect(api).to have_received(:delete_event).with("cal-1", external_id)
      expect(CalendarSyncEvent.where(integration: integration)).to be_empty
    end

    it "takes a kind of event off when it is switched off, and leaves old dates alone" do
      old = show_at(2.months.ago)
      integration.calendar_sync_events.create!(syncable_type: "Show", syncable_id: old.id, external_id: "old-1", digest: "x", synced_at: 2.months.ago)
      show_at(showtime + 1.day, event_type: "rehearsal")
      kept = show_at
      sync.sync_all!
      integration.update!(settings: integration.settings.merge("event_types" => { "rehearsal" => false }))

      described_class.new(integration.reload).sync_all!

      expect(api).to have_received(:delete_event).once
      expect(CalendarSyncEvent.where(integration: integration).pluck(:syncable_id)).to contain_exactly(old.id, kept.id)

      # A rental's times moving rewrites its show's block.
      contract = create(:contract, :active, organization: org)
      rental = contract.space_rentals.create!(location: location, location_space: ruse, starts_at: showtime + 2.days, ends_at: showtime + 2.days + 3.hours, confirmed: true)
      contracted = show_at(showtime + 2.days, location_space: ruse, space_rental: rental)
      described_class.new(integration.reload).sync_record!("SpaceRental", rental.id)
      expect(CalendarSyncEvent.where(integration: integration, syncable_type: "Show", syncable_id: contracted.id)).to exist
      expect(CalendarSyncEvent.where(integration: integration, syncable_type: "SpaceRental")).to be_empty
    end

    # A disconnect forgets every row, and a calendar kept from an earlier
    # connection still holds what was on it then (Tim, 2026-11-12): an event
    # of ours with nothing behind it any more comes off.
    it "takes off our own events that nothing in CocoScout stands behind, and nothing else" do
      show = show_at
      at = ->(time) { { "dateTime" => time.iso8601 } }
      allow(api).to receive(:list_events).with("cal-1", time_min: anything, page_token: nil)
        .and_return({ "items" => [ { "id" => "cocoevent#{show.id}", "start" => at.(showtime) },
                                   { "id" => "cocoevent999999", "start" => at.(showtime + 1.day) },
                                   { "id" => "cocorental999999", "start" => at.(showtime + 2.days) },
                                   { "id" => "cocoevent888888", "start" => at.(10.minutes.ago) },
                                   { "id" => "someonesown", "start" => at.(showtime) } ],
                      "nextPageToken" => "p2" })
      allow(api).to receive(:list_events).with("cal-1", time_min: anything, page_token: "p2")
        .and_return({ "items" => [ { "id" => "cocoevent777777", "start" => at.(showtime + 3.days) } ] })

      sync.sync_all!

      expect(api).to have_received(:delete_event).with("cal-1", "cocoevent999999")
      expect(api).to have_received(:delete_event).with("cal-1", "cocorental999999")
      expect(api).to have_received(:delete_event).with("cal-1", "cocoevent777777")
      expect(api).to have_received(:delete_event).exactly(3).times
    end

    # Only from now on (Tim, 2026-11-11).
    it "never writes, rewrites or removes a date that has already happened" do
      past = show_at(2.hours.ago)
      integration.calendar_sync_events.create!(syncable_type: "Show", syncable_id: past.id, external_id: "past-1", digest: "x", synced_at: 1.day.ago)
      unlisted = show_at(3.days.ago)
      ended = create(:contract, :active, organization: org)
      ended.space_rentals.create!(location: location, location_space: ruse, starts_at: 2.days.ago, ends_at: 2.days.ago + 3.hours, confirmed: true)

      sync.sync_all!(force: true)
      past.update!(canceled: true)
      described_class.new(integration.reload).sync_all!
      described_class.new(integration.reload).sync_record!("Show", past.id)
      described_class.new(integration.reload).sync_record!("Show", unlisted.id)

      expect(api).not_to have_received(:insert_event)
      expect(api).not_to have_received(:update_event)
      expect(api).not_to have_received(:delete_event)
      expect(CalendarSyncEvent.where(integration: integration).pluck(:external_id)).to eq([ "past-1" ])
    end

    it "waits and tries again when Google says slow down, and leaves a beat between events" do
      show_at
      show_at(showtime + 1.day)
      refusals = 2
      allow(api).to receive(:insert_event) do
        raise GoogleCalendarApi::RateLimited, "Rate Limit Exceeded" if (refusals -= 1) >= 0

        { "id" => "g#{SecureRandom.hex(3)}" }
      end

      sync.sync_all!

      expect(CalendarSyncEvent.where(integration: integration).count).to eq(2)
      expect(pauses).to eq([ 2, 4, 0.25, 0.25 ])
      expect(integration.reload.status).to eq("connected")
    end

    it "says so plainly when Google keeps refusing, and keeps what was written" do
      show_at
      allow(api).to receive(:insert_event).and_raise(GoogleCalendarApi::RateLimited, "Rate Limit Exceeded")

      expect { sync.sync_all! }.to raise_error(GoogleCalendarApi::RateLimited)

      expect(integration.reload.last_error).to eq("Google asked CocoScout to slow down. The rest of your dates will be added in a few minutes.")
    end

    it "gives each event an id of its own, and writes over one Google already has" do
      show = show_at
      allow(api).to receive(:insert_event).and_raise(GoogleCalendarApi::Conflict, "The requested identifier already exists.")

      sync.sync_all!

      expect(api).to have_received(:insert_event).with("cal-1", hash_including(id: "cocoevent#{show.id}"))
      expect(api).to have_received(:update_event).with("cal-1", "cocoevent#{show.id}", hash_including(status: "confirmed"))
      expect(CalendarSyncEvent.where(integration: integration).sole.external_id).to eq("cocoevent#{show.id}")
    end

    it "writes every coming date again at night, and makes anew one Google no longer has" do
      show_at
      sync.sync_all!
      allow(api).to receive(:update_event).and_raise(GoogleCalendarApi::NotFound, "Not Found")

      described_class.new(integration.reload).sync_all!(force: true)

      expect(api).to have_received(:update_event).once
      expect(api).to have_received(:insert_event).twice
      expect(integration.calendar_sync_events.sole.external_id).to eq("g2")
    end

    it "gets a fresh pass from Google when the last one is nearly spent" do
      integration.update!(tokens: integration.tokens.merge("expires_at" => 1.minute.ago.iso8601))
      allow(GoogleCalendarApi).to receive(:refresh).with("ref").and_return({ "access_token" => "tok2", "expires_at" => 1.hour.from_now.iso8601 })
      allow(GoogleCalendarApi).to receive(:new).with("tok2").and_return(api)
      show_at

      sync.sync_all!

      expect(integration.reload.access_token).to eq("tok2")
      expect(integration.refresh_token).to eq("ref")
      expect(api).to have_received(:insert_event).once
    end

    it "says to connect again when Google has withdrawn access" do
      show_at
      allow(api).to receive(:insert_event).and_raise(GoogleCalendarApi::Unauthorized, "invalid_grant")

      sync.sync_all!

      expect(integration.reload.status).to eq("error")
      expect(integration.last_error).to include("Connect Google Calendar again")
    end
  end

  describe "keeping up as dates change" do
    it "queues the one date when a show is made, moved, canceled or deleted" do
      show = nil
      expect { show = show_at }.to have_enqueued_job(GoogleCalendarSyncJob).with(org.id, "Show", kind_of(Integer))
      expect { show.update!(canceled: true) }.to have_enqueued_job(GoogleCalendarSyncJob).with(org.id, "Show", show.id)
      expect { show.destroy! }.to have_enqueued_job(GoogleCalendarSyncJob).with(org.id, "Show", show.id)
    end

    it "queues nothing for an organization with no calendar" do
      integration.disconnect!

      expect { show_at }.not_to have_enqueued_job(GoogleCalendarSyncJob)
    end

    it "removes a deleted show's event" do
      show = show_at
      sync.sync_all!
      external_id = integration.calendar_sync_events.sole.external_id
      show.destroy!

      described_class.for(org.id).sync_record!("Show", show.id)

      expect(api).to have_received(:delete_event).with("cal-1", external_id)
      expect(CalendarSyncEvent.where(integration: integration)).to be_empty
    end

    it "puts a contract's rentals on when it goes live" do
      contract = create(:contract, organization: org)

      expect { contract.update!(status: :active) }.to have_enqueued_job(GoogleCalendarFullSyncJob).with(org.id)
    end
  end
end
