# frozen_string_literal: true

require "rails_helper"

# One answer per show to "where do people get tickets?" (Round 9 §3).
RSpec.describe TicketLink do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19)) }

  describe ".recognize" do
    it "names the sites it knows, guesses the rest, and adds the scheme" do
      expect(described_class.recognize("www.tickettailor.com/events/sg/123")).to include(url: "https://www.tickettailor.com/events/sg/123", name: "Ticket Tailor", known: true)
      expect(described_class.recognize("https://www.eventbrite.co.uk/e/x")).to include(name: "Eventbrite", known: true)
      expect(described_class.recognize("https://tickets.mysticketshop.com/show")).to include(name: "Mysticketshop", known: false)
      expect(described_class.recognize("not a link")).to be_nil
      expect(described_class.recognize("")).to be_nil
    end
  end

  describe ".for" do
    it "links a date on sale here with its short link, and says how it stands" do
      TicketingProfile.for(org).update!(enabled: true)
      listing = TicketListing.create!(show: show, status: "on_sale")
      general = listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 2)

      link = described_class.for(show)
      expect([ link.kind, link.label, link.state ]).to eq([ :cocoscout, "Get tickets", :on_sale ])
      expect(link.url).to include("/t/#{ShortLink.canonical_for!(production).code}/#{ShortLink.date_suffix(show)}")

      listing.update!(on_sale_at: 2.days.from_now)
      expect(described_class.for(show).label).to start_with("On sale ")
      listing.update!(on_sale_at: nil)

      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_link")
      expect(described_class.for(show).label).to eq("Sold out")
    end

    it "hides a CocoScout link from the public while the box office is closed, and a draft" do
      listing = TicketListing.create!(show: show, status: "on_sale")
      expect(described_class.for(show).kind).to eq(:cocoscout)
      expect(described_class.for(show, public: true).kind).to eq(:none)
      listing.update!(status: "draft")
      expect(described_class.for(show).kind).to eq(:none)
    end

    it "falls back to the date's own link, then the production's, and respects no tickets" do
      expect(described_class.for(show).kind).to eq(:none)
      production.update!(tickets_mode: "elsewhere", tickets_url: "https://www.tickettailor.com/events/sg")
      expect(described_class.for(show)).to have_attributes(kind: :outside, url: "https://www.tickettailor.com/events/sg", site: "Ticket Tailor", label: "Get tickets")
      show.update!(tickets_mode: "elsewhere", tickets_url: "https://www.eventbrite.com/e/1")
      expect(described_class.for(show)).to have_attributes(url: "https://www.eventbrite.com/e/1", site: "Eventbrite")
      show.update!(tickets_mode: "none", tickets_url: nil)
      expect(described_class.for(show).kind).to eq(:none) # the date says no tickets, whatever the production says
      show.update!(tickets_mode: nil)
      production.update!(tickets_mode: "none", tickets_url: nil)
      expect(described_class.for(show).kind).to eq(:none)
    end
  end

  it "answers many shows at once, the same as one at a time" do
    TicketingProfile.for(org).update!(enabled: true)
    other = create(:show, production: production, date_and_time: 9.days.from_now)
    elsewhere = create(:show, production: create(:production, organization: org, tickets_mode: "elsewhere", tickets_url: "https://hottix.org/x"), date_and_time: 3.days.from_now)
    TicketListing.create!(show: show, status: "on_sale")
    shows = Show.where(id: [ show.id, other.id, elsewhere.id ]).includes(:production).to_a

    links = described_class.for_all(shows, public: true)
    expect(links.transform_values(&:kind)).to eq(show.id => :cocoscout, other.id => :none, elsewhere.id => :outside)
    expect(links[show.id].url).to eq(described_class.for(show).url)
  end
end
