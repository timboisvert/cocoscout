# frozen_string_literal: true

require "rails_helper"

# The show wizard's review says what the production's Tickets answer means for
# the new date(s), and "Not this one" keeps them off CocoScout (Round 9 §3).
RSpec.describe "Show wizard and the Tickets question", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:location) { create(:location, organization: org) }
  let(:wizard_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(wizard_cache)
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def walk_to_review
    post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
    post manage_shows_wizard_save_schedule_path(production), params: {
      event_frequency: "recurring", duration_minutes: "120", recurrence_start_datetime: 2.weeks.from_now.change(hour: 20).strftime("%Y-%m-%dT%H:%M"),
      recurrence_pattern: "weekly", recurrence_end_date: 5.weeks.from_now.to_date.iso8601
    }
    post manage_shows_wizard_save_location_path(production), params: { is_online: "false", location_id: location.id }
    post manage_shows_wizard_save_details_path(production), params: { secondary_name: "" }
  end

  it "says the dates go on sale right away, and keeps them off CocoScout on request" do
    walk_to_review
    get manage_shows_wizard_review_path(production)
    expect(response.body).to include("Each date goes on sale on CocoScout right away", "General $20.00", "Not this one")

    post manage_shows_wizard_create_path(production), params: { exclude_from_tickets: "1" }
    shows = production.shows.order(:date_and_time).to_a
    expect(shows.size).to be >= 3
    setup = production.production_ticketing.reload
    expect(setup.excluded_show_ids).to match_array(shows.map(&:id))
    expect(setup.matching_shows).to be_empty
    ProductionTicketingDates.sync!(setup)
    expect(TicketListing.where(show_id: shows.map(&:id))).to be_empty
  end

  it "lists the dates when nothing says otherwise" do
    walk_to_review
    post manage_shows_wizard_create_path(production)
    setup = production.production_ticketing.reload
    expect(setup.excluded_show_ids).to eq([])
    ProductionTicketingDates.sync!(setup)
    expect(TicketListing.where(show_id: production.shows.select(:id)).count).to eq(production.shows.count)
  end
end
