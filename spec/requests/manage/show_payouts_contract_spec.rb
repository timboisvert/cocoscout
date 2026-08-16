# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ShowPayouts contract shows", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:show) { create(:show, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def payable_person
    p = create(:person)
    p.update!(stripe_account_id: "acct_p#{p.id}", payouts_enabled: true)
    p
  end

  it "shows the contract payout (not the casting flow) with a pay action for an owed payment" do
    person = payable_person
    contractor = create(:contractor, organization: org, person: person, name: "Lighting Co")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    create(:contract_payment, contract: contract, show: show, direction: "outgoing",
                              status: "pending", amount: 500, due_date: Date.current)

    get manage_money_show_payout_path(show)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contract payout")
    expect(response.body).to include("Lighting Co")
    expect(response.body).to include("Add to payout run")
    # Not the casting flow.
    expect(response.body).not_to include("Calculate Payout")
  end

  it "settles a per-event rental on its contract rather than offering a payout scheme" do
    # A per-event fee deal never writes show_id onto its payments, so the show
    # has to be recognized by the contract that booked it.
    contractor = create(:contractor, organization: org, person: create(:person), name: "Tommy Corts")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name,
                                           draft_data: {
                                             "payment_structure" => "per_event",
                                             "payment_config" => { "per_event_amount" => "300", "per_event_direction" => "incoming" }
                                           })
    rental = create(:space_rental, contract: contract, starts_at: show.date_and_time)
    show.update!(space_rental: rental)
    create(:contract_payment, contract: contract, direction: "incoming", status: "pending",
                              amount: 300, due_date: show.date_and_time.to_date, description: "Event 2 Fee")

    get manage_money_show_payout_path(show)

    expect(response.body).to include("Contract payout")
    expect(response.body).to include("Event 2 Fee")
    expect(response.body).not_to include("Payout Scheme")
  end

  it "flags a contractor with no connected bank instead of offering to pay" do
    contractor = create(:contractor, organization: org, person: create(:person), name: "No Bank Co")
    contract = create(:contract, :active, organization: org, production: production,
                                           contractor: contractor, contractor_name: contractor.name)
    create(:contract_payment, contract: contract, show: show, direction: "outgoing",
                              status: "pending", amount: 500, due_date: Date.current)

    get manage_money_show_payout_path(show)

    expect(response.body).to include("Contract payout")
    expect(response.body).to include("Needs bank")
    expect(response.body).not_to include("Add to payout run")
  end
end
