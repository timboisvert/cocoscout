# frozen_string_literal: true

require "rails_helper"

# Phase 7: the amend Financials step uses the same editor as the create wizard,
# and the review surfaces real scheduling conflicts (same room, same time) behind
# an acknowledge-to-proceed modal.
RSpec.describe "Manage::Contracts amend financials & conflicts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:space) { location.location_spaces.create!(name: "Main Room") }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the Financials step" do
    it "renders the shared who-sells / settlement editor" do
      get amend_payments_manage_contract_path(contract)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Who sells the tickets?")
      expect(response.body).to include("How does the money work?")
    end

    it "stages the deal config and payment list into amend_data" do
      post save_amend_payments_manage_contract_path(contract), params: {
        who_sells_tickets: "contractor",
        payment_structure: "revenue_share",
        payment_config: { "revenue_our_share" => 30, "revenue_their_share" => 70, "revenue_settlement" => "monthly" }.to_json,
        payments: [ { "description" => "Revenue Share Settlement", "amount" => 0, "amount_tbd" => true } ].to_json,
        offline_payment_methods: [ "check" ]
      }

      expect(response).to redirect_to(amend_ticketing_tech_manage_contract_path(contract))
      amend = contract.reload.amend_data
      expect(amend["payment_structure"]).to eq("revenue_share")
      expect(amend["payment_config"]["who_sells_tickets"]).to eq("contractor")
      expect(amend["payment_config"]["settlement_basis"]).to eq("revenue_share")
      expect(amend["payments"].first["direction"]).to eq("incoming") # they sell → they owe us
    end

    it "reconciles payments on apply, preserving paid ones and replacing pending" do
      paid = create(:contract_payment, :paid, contract: contract, description: "Deposit", amount: 200, direction: "incoming")
      create(:contract_payment, contract: contract, description: "Old pending", amount: 500, direction: "incoming", status: "pending")

      contract.update_amend_data(
        "payment_structure" => "flat_fee",
        "payment_config" => { "flat_fee_direction" => "incoming", "who_sells_tickets" => nil, "settlement_basis" => "flat" },
        "payments" => [ { "description" => "Rental fee", "amount" => 750, "direction" => "incoming", "due_date" => 1.month.from_now.to_date.to_s } ]
      )

      post apply_amendments_manage_contract_path(contract)

      contract.reload
      descriptions = contract.contract_payments.pluck(:description)
      expect(descriptions).to include("Deposit")     # paid — preserved
      expect(descriptions).to include("Rental fee")  # staged — created
      expect(descriptions).not_to include("Old pending") # pending — replaced
      expect(paid.reload.status).to eq("paid")
    end
  end

  describe "conflict detection on review" do
    # An existing booking in the Main Room, 7–10pm next month.
    let(:existing_start) { 1.month.from_now.change(hour: 19, min: 0) }
    let!(:existing_rental) do
      create(:space_rental, contract: contract, location: location, location_space: space,
        starts_at: existing_start, ends_at: existing_start.change(hour: 22))
    end

    it "shows the conflict bar and modal when a new event overlaps the same room" do
      contract.update_amend_data(
        "new_bookings" => [ {
          "location_id" => location.id, "space_id" => space.id,
          "starts_at" => existing_start.change(hour: 20).iso8601, "duration" => "2"
        } ]
      )

      get amend_review_manage_contract_path(contract)

      expect(response.body).to include("View the conflict")
      expect(response.body).to include("scheduling conflict")
      expect(response.body).to include("Main Room")
      expect(response.body).to include("data-controller=\"contract-conflict\"")
    end

    it "shows no conflict when the new event is in the same room at a different time" do
      contract.update_amend_data(
        "new_bookings" => [ {
          "location_id" => location.id, "space_id" => space.id,
          "starts_at" => existing_start.change(hour: 23).iso8601, "duration" => "1"
        } ]
      )

      get amend_review_manage_contract_path(contract)

      expect(response.body).not_to include("View the conflict")
    end

    it "shows no conflict for an entire-venue booking (no specific room)" do
      contract.update_amend_data(
        "new_bookings" => [ {
          "location_id" => location.id, "space_id" => "",
          "starts_at" => existing_start.change(hour: 20).iso8601, "duration" => "2"
        } ]
      )

      get amend_review_manage_contract_path(contract)

      expect(response.body).not_to include("View the conflict")
    end
  end
end
