# frozen_string_literal: true

require "rails_helper"

# Phase 7b: during an amendment you can set an event's actual time within its
# booked slot (a 3-hour booking where the show runs in the middle hour), and the
# linked show moves to match.
RSpec.describe "Manage::Contracts amend event times", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  # A 3-hour booking, 6–9pm.
  let(:slot_start) { 1.month.from_now.change(hour: 18, min: 0) }
  let(:slot_end)   { 1.month.from_now.change(hour: 21, min: 0) }
  let!(:rental) do
    create(:space_rental, contract: contract, location: location, starts_at: slot_start, ends_at: slot_end)
  end
  let!(:show) do
    production.shows.create!(date_and_time: slot_start, duration_minutes: 180, location: location, space_rental: rental)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the event-time editor prefilled with the booked slot" do
    get amend_events_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Event times")
    expect(response.body).to include("Different show time")
  end

  it "stages an event time within the slot, without touching the live rental" do
    post save_amend_events_manage_contract_path(contract), params: {
      event_times: { rental.id.to_s => { enabled: "1", starts_at: "#{slot_start.strftime('%Y-%m-%d')}T19:00", ends_at: "#{slot_start.strftime('%Y-%m-%d')}T20:30" } }
    }

    expect(response).to redirect_to(amend_payments_manage_contract_path(contract))
    expect(rental.reload.event_starts_at).to be_nil # not applied yet
    expect(contract.reload.amend_data["event_times"][rental.id.to_s]["starts_at"]).to include("T19:00")
  end

  it "applies the event time to the rental and moves the show to match" do
    contract.update_amend_data(
      "event_times" => { rental.id.to_s => { "starts_at" => "#{slot_start.strftime('%Y-%m-%d')}T19:00", "ends_at" => "#{slot_start.strftime('%Y-%m-%d')}T20:30" } }
    )

    post apply_amendments_manage_contract_path(contract)

    rental.reload
    expect(rental.event_starts_at.hour).to eq(19)
    expect(rental.event_ends_at.hour).to eq(20)

    show.reload
    expect(show.date_and_time.hour).to eq(19)
    expect(show.duration_minutes).to eq(90)
  end

  it "carries a separate event time on a newly added booking through to its show" do
    new_date = 2.months.from_now.to_date

    post save_amend_bookings_manage_contract_path(contract), params: {
      booking_mode: "multiple",
      booking_rules_json: [
        {
          mode: "single",
          location_id: location.id,
          space_id: "",
          starts_at: "#{new_date}T18:00",
          duration: "3",
          notes: "",
          event_type: "show",
          event_starts_at: "#{new_date}T19:00",
          event_ends_at: "#{new_date}T20:30"
        }
      ].to_json,
      removed_rental_ids: "[]"
    }

    staged = contract.reload.amend_data["new_bookings"]
    expect(staged.size).to eq(1)
    expect(staged.first["event_starts_at"]).to include("T19:00")

    expect { post apply_amendments_manage_contract_path(contract) }
      .to change { contract.space_rentals.count }.by(1)

    new_rental = contract.space_rentals.order(:created_at).last
    expect(new_rental.event_starts_at.hour).to eq(19)
    expect(new_rental.event_ends_at.hour).to eq(20)

    new_show = new_rental.shows.first
    expect(new_show.date_and_time.hour).to eq(19)
    expect(new_show.duration_minutes).to eq(90)
  end

  it "rejects an event time outside the booked slot and rolls back" do
    contract.update_amend_data(
      "event_times" => { rental.id.to_s => { "starts_at" => "#{slot_start.strftime('%Y-%m-%d')}T17:00", "ends_at" => "#{slot_start.strftime('%Y-%m-%d')}T18:30" } }
    )

    post apply_amendments_manage_contract_path(contract)

    # The invalid edit is not applied; the show stays put.
    expect(rental.reload.event_starts_at).to be_nil
    expect(show.reload.date_and_time.hour).to eq(18)
  end
end
