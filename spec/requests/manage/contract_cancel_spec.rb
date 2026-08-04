# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Contracts cancel page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def build_rental_show!(starts_at:)
    rental = SpaceRental.create!(
      contract: contract, location: location,
      starts_at: starts_at, ends_at: starts_at + 3.hours,
      allow_overlap: true
    )
    create(:show, production: production, location: location,
           space_rental: rental, date_and_time: starts_at + 30.minutes)
  end

  it "renders with rental-backed shows and pending payments" do
    build_rental_show!(starts_at: 2.weeks.from_now.change(hour: 19))
    build_rental_show!(starts_at: 3.weeks.from_now.change(hour: 19))
    contract.contract_payments.create!(description: "Deposit", amount: 100,
                                       direction: "incoming", due_date: 1.week.from_now, status: "pending")

    get cancel_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cancel Contract")
  end

  it "renders with a show that has no rental and no production shows" do
    show = create(:show, production: production, location: location,
                  date_and_time: 2.weeks.from_now)

    get cancel_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
  end

  it "renders with no shows and no payments" do
    get cancel_manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
  end

  describe "process_cancel with rows referencing the contract's shows" do
    let!(:show) { build_rental_show!(starts_at: 2.weeks.from_now.change(hour: 19)) }

    it "cancels despite synced calendar events on a show, scheduling remote cleanup" do
      subscription = CalendarSubscription.create!(person: create(:person), provider: "google")
      event = CalendarEvent.create!(calendar_subscription: subscription, show: show, provider_event_id: "evt_1")
      # Rows that reference the production would block deleting it, too
      AuditionWizardState.create!(production: production, user: owner)

      expect {
        post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all" }
      }.to have_enqueued_job(CalendarEventCleanupJob).with(subscription.id, "evt_1")

      expect(response).to redirect_to(manage_contracts_path)
      expect(contract.reload.status).to eq("cancelled")
      expect(Show.exists?(show.id)).to be(false)
      expect(CalendarEvent.exists?(event.id)).to be(false)
      expect(Production.exists?(production.id)).to be(false)
    end

    it "cancels despite a staffing shift covering a show" do
      shift = create(:shift, organization: org)
      ShiftShow.create!(shift: shift, show: show)

      post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all" }

      expect(response).to redirect_to(manage_contracts_path)
      expect(contract.reload.status).to eq("cancelled")
      expect(Show.exists?(show.id)).to be(false)
    end

    it "cancels a revenue-share per-event contract whose financials sync would re-link a payment (FK regression)" do
      contract.update!(draft_data: {
        "payment_structure" => "revenue_share",
        "payment_config" => {
          "revenue_our_share" => 80,
          "revenue_their_share" => 20,
          "revenue_settlement" => "per_event"
        }
      })
      create(:show_financials, show: show)
      payment = contract.contract_payments.create!(
        description: "Revenue Share Settlement", amount: 0, amount_tbd: true,
        direction: "incoming", due_date: show.date_and_time.to_date, status: "pending"
      )

      post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all" }

      expect(response).to redirect_to(manage_contracts_path)
      expect(contract.reload.status).to eq("cancelled")
      expect(Show.exists?(show.id)).to be(false)
      expect(payment.reload.show_id).to be_nil
      expect(payment.status).to eq("cancelled")
    end

    it "cancels despite messages tied to a show, keeping the messages" do
      message = create(:message, organization: org, show: show, visibility: :show)

      post process_cancel_manage_contract_path(contract), params: { settlement_type: "cancel_all" }

      expect(response).to redirect_to(manage_contracts_path)
      expect(contract.reload.status).to eq("cancelled")
      expect(Show.exists?(show.id)).to be(false)
      expect(message.reload.show_id).to be_nil
    end
  end
end
