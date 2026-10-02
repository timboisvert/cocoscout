# frozen_string_literal: true

require "rails_helper"

# Ticketing set up once for a repeating production, the way sign-ups handle
# repeating events: it says which of the production's events are included
# (all performances, some event types, or dates picked by hand) and when each
# one's sales open; every included show gets a listing that reads the
# production's settings unless it has its own, and the production's ticket
# types stay in sync on every show that uses them.
RSpec.describe ProductionTicketing do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:setup) do
    described_class.for(production).tap do |pt|
      pt.update!(enabled: true, schedule_mode: "relative", opens_days_before: 30, online_close_minutes: 60,
                 door_note: "Doors at 7", max_per_order: 6)
      pt.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 70, position: 0)
      pt.ticket_tiers.create!(name: "Student", price_cents: 1_500, position: 1)
    end
  end

  def show_on(days, type: :show, canceled: false)
    create(:show, production: production, event_type: type, canceled: canceled,
                  date_and_time: days.days.from_now.change(hour: 19, min: 30))
  end

  describe "which shows are included" do
    it "lists every upcoming performance, each opening N days before, inheriting the production's prices" do
      soon = show_on(5)
      later = show_on(45)
      class_night = show_on(8, type: :class)
      rehearsal = show_on(6, type: :rehearsal)
      canceled = show_on(7, canceled: true)

      result = ProductionTicketingDates.sync!(setup)

      expect(result.added.map(&:show)).to contain_exactly(soon, later, class_night)
      expect([ rehearsal, canceled ].map(&:ticket_listing)).to all(be_nil)
      listing = soon.reload.ticket_listing
      expect(listing.attributes.slice("status", "inherits_tiers")).to eq("status" => "on_sale", "inherits_tiers" => true)
      expect(listing.ticket_tiers.map { |t| [ t.name, t.price_cents, t.quantity, t.source_tier_id.present? ] })
        .to eq([ [ "General", 2_000, 70, true ], [ "Student", 1_500, nil, true ] ])
      expect([ listing.on_sale_at, listing.off_sale_at ]).to eq([ soon.date_and_time - 30.days, soon.date_and_time - 1.hour ])
      expect(listing.selling?).to be(true)
      expect(later.reload.ticket_listing.selling?).to be(false) # opens in 15 days

      expect(ProductionTicketingDates.sync!(setup).added).to be_empty # idempotent
    end

    it "can take only some event types, or dates picked by hand, and drops dates nobody has bought" do
      show_night = show_on(5)
      class_night = show_on(8, type: :class)
      setup.update!(event_matching: "event_types", event_type_filter: [ "class" ])
      expect(ProductionTicketingDates.sync!(setup).added.map(&:show)).to eq([ class_night ])

      setup.update!(event_matching: "manual")
      setup.production_ticketing_shows.create!(show: show_night)
      result = ProductionTicketingDates.sync!(setup)
      expect(result.added.map(&:show)).to eq([ show_night ])
      expect(result.removed.map(&:show_id)).to eq([ class_night.id ])
      expect(class_night.reload.ticket_listing).to be_nil
    end

    it "keeps a date someone bought for, even when it stops matching" do
      class_night = show_on(8, type: :class)
      ProductionTicketingDates.sync!(setup)
      listing = class_night.reload.ticket_listing
      create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: Time.current, expires_at: nil)

      setup.update!(event_matching: "event_types", event_type_filter: [ "show" ])
      result = ProductionTicketingDates.sync!(setup)
      expect(result.kept).to eq([ listing ])
      expect(listing.reload).to be_persisted
    end

    it "goes on sale right away when sales open as soon as a date is listed" do
      setup.update!(schedule_mode: "immediate")
      far = show_on(90)
      ProductionTicketingDates.sync!(setup)
      expect(far.reload.ticket_listing.on_sale_at).to be_nil
      expect(far.ticket_listing.selling?).to be(true)
    end

    it "leaves a show that already has its own listing, and does nothing while ticketing is off" do
      hand_made = TicketListing.create!(show: show_on(3), status: "draft")
      setup.update!(enabled: false)
      show_on(4)
      expect(ProductionTicketingDates.sync!(setup).added).to be_empty

      setup.update!(enabled: true)
      expect(ProductionTicketingDates.sync!(setup).added.size).to eq(1)
      expect(hand_made.reload.attributes.slice("status", "inherits_tiers")).to eq("status" => "draft", "inherits_tiers" => false)
    end

    it "stops its dates selling when switched off, and resumes them when switched on" do
      show_on(5)
      ProductionTicketingDates.sync!(setup)
      listing = TicketListing.sole
      expect(listing.selling?).to be(true)

      setup.update!(enabled: false)
      ProductionTicketingDates.switch!(setup, on: false)
      expect([ listing.reload.status, listing.selling? ]).to eq([ "paused", false ])

      show_on(6)
      setup.update!(enabled: true)
      ProductionTicketingDates.switch!(setup, on: true)
      ProductionTicketingDates.sync!(setup)
      expect(listing.reload.status).to eq("on_sale")
      expect(TicketListing.count).to eq(2)
    end

    it "adds a new show as soon as it's on the calendar" do
      setup
      expect { show_on(10) }.to have_enqueued_job(ProductionTicketingDatesJob).with(setup.id)
    end

    it "moves inheriting shows to a new schedule, leaving one given its own" do
      a = show_on(5)
      b = show_on(6)
      ProductionTicketingDates.sync!(setup)
      own = b.reload.ticket_listing
      own.update!(on_sale_at: 1.day.ago)

      was = setup.dup
      setup.update!(opens_days_before: 10, online_close_minutes: 0)
      ProductionTicketingDates.reschedule!(setup, was: was)
      expect([ a.reload.ticket_listing.on_sale_at, a.ticket_listing.off_sale_at ]).to eq([ a.date_and_time - 10.days, a.date_and_time ])
      expect(own.reload.on_sale_at).to be_within(1.second).of(1.day.ago)
    end
  end

  describe "a show reads the production's settings unless it has its own" do
    it "inherits the title, words, notes, fees and limit" do
      setup.update!(title: "Rising Stars Showcase", description: "New comics.", fee_mode: "org")
      show_on(2)
      listing = ProductionTicketingDates.sync!(setup).added.sole

      expect([ listing.display_title, listing.effective_description, listing.effective_door_note,
               listing.effective_fee_mode, listing.effective_max_per_order ])
        .to eq([ "Rising Stars Showcase", "New comics.", "Doors at 7", "org", 6 ])

      listing.update!(title: "Holiday Showcase", door_note: "Doors at 6:30", fee_mode: "buyer")
      expect([ listing.display_title, listing.effective_door_note, listing.effective_fee_mode ])
        .to eq([ "Holiday Showcase", "Doors at 6:30", "buyer" ])
    end
  end

  describe "keeping ticket types in sync" do
    it "follows the production's prices, new types, order and removals; a show with its own is left alone" do
      show_on(2)
      show_on(3)
      inheriting, own = ProductionTicketingDates.sync!(setup).added.sort_by(&:show_id)
      own.update!(inherits_tiers: false)
      general, student = setup.ticket_tiers.to_a

      general.update!(price_cents: 2_500)
      student.update!(position: 0)
      general.update!(position: 1)
      setup.ticket_tiers.create!(name: "VIP", price_cents: 4_000, position: 2)
      ProductionTicketingSync.sync_all!(setup)

      expect(inheriting.ticket_tiers.reload.active.map { |t| [ t.name, t.price_cents ] })
        .to eq([ [ "Student", 1_500 ], [ "General", 2_500 ], [ "VIP", 4_000 ] ])
      expect(own.ticket_tiers.reload.map(&:price_cents)).to eq([ 2_000, 1_500 ])

      student.destroy!
      ProductionTicketingSync.sync_all!(setup)
      expect(inheriting.ticket_tiers.reload.map(&:name)).to eq([ "General", "VIP" ]) # Student, never sold, is gone
    end

    it "keeps a show's seats when the production's would drop below what it sold" do
      show_on(2)
      listing = ProductionTicketingDates.sync!(setup).added.sole
      tier = listing.ticket_tiers.find_by!(name: "General")
      order = create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: Time.current, expires_at: nil)
      3.times { create(:ticket, ticket_order: order, ticket_tier: tier) }

      setup.ticket_tiers.find_by!(name: "General").update!(quantity: 2)
      result = ProductionTicketingSync.sync_all!(setup)
      expect(result.skipped.map(&:id)).to eq([ tier.id ])
      expect(tier.reload.quantity).to eq(70)
    end
  end

  it "moves the sales window when the show moves" do
    show = show_on(2)
    listing = ProductionTicketingDates.sync!(setup).added.sole
    show.update!(date_and_time: show.date_and_time + 1.day)
    expect([ listing.reload.on_sale_at, listing.off_sale_at ]).to eq([ show.date_and_time - 30.days, show.date_and_time - 1.hour ])
  end
end
