# frozen_string_literal: true

require "rails_helper"

# Amend event times: the actual show time within a booked slot is set when ADDING
# an event on the bookings step (a 3-hour booking where the show runs the middle
# hour). The review-events step only displays it; it can't be edited there.
RSpec.describe "Manage::Contracts amend event times", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "no longer offers an event-time editor on the review step" do
    get amend_events_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Different show time")
    expect(response.body).not_to include('name="event_times')
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

  it "displays the alternate show time on the review-events step" do
    new_date = 2.months.from_now.to_date
    contract.update_amend_data(
      "new_bookings" => [ {
        "location_id" => location.id, "space_id" => "",
        "starts_at" => "#{new_date}T18:00:00", "duration" => "3",
        "event_starts_at" => "#{new_date}T19:00:00", "event_ends_at" => "#{new_date}T20:30:00"
      } ]
    )

    get amend_events_manage_contract_path(contract)

    expect(response.body).to include("Show runs")
    expect(response.body).to match(/Show runs\s*7:00 PM - 8:30 PM/)
  end
end
