# frozen_string_literal: true

require "rails_helper"

# What a show needs (after-V1 #6): its production's services, its contract's
# (per-event lines on their dates, once lines on every show), and the show's
# own changes.
RSpec.describe ShowServices do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Halloween o' Weens") }
  let!(:booth) { org.house_services.create!(name: "Booth Tech", position: 0).tap { |s| s.house_roles << create(:house_role, organization: org, name: "Booth Tech") } }
  let!(:security) { org.house_services.create!(name: "Security", position: 1).tap { |s| s.house_roles << create(:house_role, organization: org, name: "Security") } }
  let!(:video) { org.house_services.create!(name: "Videographer", position: 2) }
  let(:friday) { create(:show, production: production, date_and_time: Time.zone.local(2026, 11, 6, 20)) }
  let(:saturday) { create(:show, production: production, date_and_time: Time.zone.local(2026, 11, 7, 20)) }

  def needs(show)
    described_class.new([ show ]).for(show).map { |n| [ n.service.name, n.people_count, n.source, n.dropped ] }
  end

  it "gives every show its production's services" do
    production.production_service_needs.create!(house_service: booth)
    production.production_service_needs.create!(house_service: security, people_count: 2)

    expect(needs(friday)).to eq([ [ "Booth Tech", 1, :production, false ], [ "Security", 2, :production, false ] ])
  end

  it "adds a signed contract's services: a per-event line on its dates, a once line on every show" do
    create(:contract, :active, organization: org, production: production, draft_data: { "services" => [
      { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "events" => [ { "starts_at" => friday.date_and_time.iso8601, "hours" => 2 } ] },
      { "name" => "videographer", "unit" => "flat" } # an older line, found by name
    ] })

    expect(needs(friday)).to eq([ [ "Booth Tech", 1, :contract, false ], [ "Videographer", 1, :contract, false ] ])
    expect(needs(saturday)).to eq([ [ "Videographer", 1, :contract, false ] ])
  end

  it "ignores a contract that isn't signed" do
    create(:contract, organization: org, production: production, draft_data: { "services" => [ { "name" => "Booth Tech", "service_id" => booth.id } ] })
    expect(needs(friday)).to be_empty
  end

  it "applies the show's own changes, and saves only what differs from the production" do
    production.production_service_needs.create!(house_service: booth)
    production.production_service_needs.create!(house_service: security)

    described_class.save!(friday, {
      booth.id.to_s => { "needed" => "1", "people" => "1" },     # same as the production: no change kept
      security.id.to_s => { "needed" => "0", "people" => "1" },  # not this show
      video.id.to_s => { "needed" => "1", "people" => "1" }      # just this show
    }, services: org.house_services.to_a)

    expect(friday.show_service_changes.map { |c| [ c.house_service.name, c.needed ] }).to contain_exactly([ "Security", false ], [ "Videographer", true ])
    expect(needs(friday)).to eq([ [ "Booth Tech", 1, :production, false ], [ "Security", 1, :production, true ], [ "Videographer", 1, :show, false ] ])
    expect(needs(saturday).map(&:first)).to eq([ "Booth Tech", "Security" ])

    # Putting Security back leaves no change behind.
    described_class.change!(friday, security, needed: true)
    expect(friday.show_service_changes.reload.map { |c| c.house_service.name }).to eq([ "Videographer" ])
  end

  it "batches a week of shows in a fixed number of queries" do
    production.production_service_needs.create!(house_service: booth)
    shows = (1..6).map { |n| create(:show, production: production, date_and_time: Time.zone.local(2026, 11, n, 20)) }
    resolver = described_class.new(Show.where(id: shows.map(&:id)).includes(:production).to_a)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { shows.each { |s| resolver.for(s) } }
    expect(queries).to eq(0)
  end
end
