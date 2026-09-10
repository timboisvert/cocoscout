# frozen_string_literal: true

require "rails_helper"

# Amend Contract mirrors Create: an event added to a live contract names its own
# kind — a rehearsal alongside the shows — instead of silently inheriting the
# contract's default event type.
RSpec.describe "Manage::Contracts amend event type", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers the event-type picker on the bookings step, the same as the create wizard" do
    get amend_bookings_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-field="event_type"')
    expect(response.body).to include("Event Type")
  end

  def stage_booking!(event_type:, date:)
    post save_amend_bookings_manage_contract_path(contract), params: {
      booking_mode: "multiple",
      booking_rules_json: [
        { mode: "single", location_id: location.id, space_id: "",
          starts_at: "#{date}T18:00", duration: "3", notes: "", event_type: event_type }
      ].to_json,
      removed_rental_ids: "[]"
    }
  end

  it "carries the chosen event type through to the show it creates" do
    stage_booking!(event_type: "rehearsal", date: 2.months.from_now.to_date)

    expect(contract.reload.amend_data["new_bookings"].first["event_type"]).to eq("rehearsal")

    post apply_amendments_manage_contract_path(contract)

    new_show = contract.space_rentals.order(:created_at).last.shows.first
    expect(new_show.event_type).to eq("rehearsal")
  end

  it "falls back to the contract's own event type when none is picked" do
    post save_amend_bookings_manage_contract_path(contract), params: {
      booking_mode: "multiple",
      booking_rules_json: [
        { mode: "single", location_id: location.id, space_id: "",
          starts_at: "#{2.months.from_now.to_date}T18:00", duration: "3", notes: "" }
      ].to_json,
      removed_rental_ids: "[]"
    }

    post apply_amendments_manage_contract_path(contract)

    new_show = contract.space_rentals.order(:created_at).last.shows.first
    expect(new_show.event_type).to eq("show")
  end

  it "names the event type on the review step" do
    stage_booking!(event_type: "workshop", date: 2.months.from_now.to_date)

    get amend_events_manage_contract_path(contract)

    expect(response.body).to include("Workshop")
  end
end
