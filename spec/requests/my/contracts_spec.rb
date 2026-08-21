# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Contracts", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:org) { create(:organization, :pro) }
  let(:contractor) { create(:contractor, organization: org, person: person, email: person.email) }
  let!(:contract) { create(:contract, :active, organization: org, contractor: contractor, contractor_name: "Sound Co") }
  let!(:payment) { create(:contract_payment, :outgoing, contract: contract, amount: 300, description: "First payment") }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists the contracts the signed-in person holds as a contractor" do
    get my_contracts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("My Contracts").and include("First payment")
  end

  it "renders a full-summary modal for each contract" do
    get my_contracts_path
    # The contract card header is the clickable trigger that opens the modal.
    expect(response.body).to include("contract-modal-#{contract.id}")
    expect(response.body).to include(%(data-modal-id="contract-modal-#{contract.id}"))
    # Modal frames the payment from the contractor's point of view — "we" is the
    # org they're looking at, named, not an abstract "we".
    expect(response.body).to include("#{org.name} pays you")
    expect(response.body).not_to include("What we pay you")
    expect(response.body).to include(org.name)
  end

  it "prompts to connect a bank when the person can't receive payouts yet" do
    get my_contracts_path
    expect(response.body).to include("Connect your bank")
  end

  it "groups multiple contracts on one production together" do
    production = create(:production, organization: org, name: "Spring Revue")
    create(:contract, :active, organization: org, contractor: contractor, production: production)
    create(:contract, :active, organization: org, contractor: contractor, production: production)

    get my_contracts_path
    # The two-per-production group shows the count label; header renders once.
    expect(response.body).to include("2 contracts")
  end

  describe "money they owe" do
    let!(:rental_contract) do
      create(:contract, :active, organization: org, contractor: contractor,
             contract_start_date: 2.weeks.ago.to_date, contract_end_date: 6.weeks.from_now.to_date,
             draft_data: {
               "payment_structure" => "per_event",
               "payment_config" => { "per_event_amount" => 50, "per_event_direction" => "incoming", "per_event_timing" => "per_event" }
             })
    end
    let!(:past_due) do
      create(:contract_payment, contract: rental_contract, direction: "incoming", amount: 50,
                                description: "Aug 19 event", due_date: 1.day.ago.to_date)
    end
    let!(:future_one) do
      create(:contract_payment, contract: rental_contract, direction: "incoming", amount: 50,
                                description: "Next week event", due_date: 1.week.from_now.to_date)
    end
    let!(:future_two) do
      create(:contract_payment, contract: rental_contract, direction: "incoming", amount: 50,
                                description: "Fortnight event", due_date: 2.weeks.from_now.to_date)
    end

    it "leads with what's already due and folds the schedule away" do
      get my_contracts_path

      body = response.body
      # The headline figure is the money due now, not the whole schedule.
      expect(body).to include("Due now")
      expect(body).to include("$50.00")
      expect(body).not_to include("You owe $150")
      # The rest is reachable but secondary.
      expect(body).to include("2 upcoming payments")
      expect(body).to include("$100.00 scheduled")
      expect(body).to include("Next week event")
    end

    it "says what the contract IS, not just its dates" do
      get my_contracts_path

      expect(response.body).to include("$50.00 per event — you pay them, paid event by event")
    end

    it "names what a rental contract books" do
      location = create(:location, organization: org, name: "Stars &amp; Garters Bar".gsub("&amp;", "&"))
      space = location.location_spaces.create!(name: "The Parlor")
      create(:space_rental, contract: rental_contract, location: location, location_space: space,
                            starts_at: 1.week.from_now.change(hour: 19))

      get my_contracts_path
      expect(response.body).to include("The Parlor at #{ERB::Util.html_escape(location.name)} · 1 booking")
    end
  end

  it "doesn't show contracts belonging to a different person" do
    other = create(:contractor, organization: org, person: create(:person), email: "other@example.com")
    create(:contract, :active, organization: org, contractor: other, contractor_name: "Other Co")
    get my_contracts_path
    expect(response.body).not_to include("Other Co")
  end
end
