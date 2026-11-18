# frozen_string_literal: true

require "rails_helper"

# My Contracts: the contractor asks the organization about one of the
# contract's dates, sees where the request stands, and can take it back.
RSpec.describe "My contract date requests", type: :request do
  let(:password) { "Password123!" }
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let!(:org) { create(:organization, :pro) }
  let!(:contractor) { create(:contractor, organization: org, person: person) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let!(:location) { create(:location, organization: org) }
  let(:night) { 1.month.from_now.in_time_zone(org.time_zone).change(hour: 20, min: 0) }
  let!(:rental) { create(:space_rental, contract: contract, location: location, starts_at: night, ends_at: night + 2.hours) }
  let!(:show) { production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "offers Request date/time change on a live contract" do
    get my_contracts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Request date/time change")
    expect(response.body).to include(my_ask_contract_date_path(contract))
  end

  it "shows the form with the contract's dates still to come" do
    get my_ask_contract_date_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(night.strftime("%a %b %-d, %-l:%M %p"))
    expect(response.body).to include("A date that isn&#39;t on the contract").or include("A date that isn't on the contract")
    expect(response.body).to include("Send request")
  end

  it "asks to move a date, reading the time in the organization's clock" do
    asked = night - 30.minutes

    expect do
      post my_ask_contract_date_path(contract), params: { show_id: show.id, kind: "move",
                                                          proposed_at: asked.strftime("%Y-%m-%dT%H:%M"), note: "We agreed on 7:30." }
    end.to change(contract.date_requests, :count).by(1)

    expect(response).to redirect_to(my_contracts_path)
    expect(flash[:notice]).to include("#{org.name} has been notified")
    request = contract.date_requests.last
    expect(request).to have_attributes(kind: "move", show: show, proposed_at: asked, note: "We agreed on 7:30.", requested_by: user)
    expect(show.reload.date_and_time).to eq(night)

    get my_contracts_path
    expect(response.body).to include("You requested to move").and include("Withdraw")
  end

  it "asks to add a date" do
    post my_ask_contract_date_path(contract), params: { show_id: "new", proposed_at: (night + 1.day).strftime("%Y-%m-%dT%H:%M") }

    expect(contract.date_requests.last).to have_attributes(kind: "add", show: nil, proposed_at: night + 1.day)
  end

  it "says why when the request can't be asked" do
    post my_ask_contract_date_path(contract), params: { show_id: show.id, kind: "question", note: "" }

    expect(response).to redirect_to(my_contracts_path)
    expect(flash[:alert]).to include("Write your question")
    expect(contract.date_requests).to be_empty
  end

  it "takes a request back" do
    request = ContractDateRequests.ask!(contract: contract, user: user, show: show, kind: "cancel")

    delete my_contract_date_request_path(contract, request_id: request.id)

    expect(response).to redirect_to(my_contracts_path)
    expect(request.reload.status).to eq("withdrawn")
  end

  it "shows the organization's answer until it's dismissed" do
    request = ContractDateRequests.ask!(contract: contract, user: user, show: show, kind: "move", proposed_at: night - 30.minutes)
    ContractDateRequests.keep!(request, user: org.owner, note: "Doors are 7:30, the show is 8.")

    get my_contracts_path
    expect(response.body).to include("#{org.name} kept").and include("Doors are 7:30, the show is 8.")

    patch my_dismiss_contract_date_request_path(contract, request_id: request.id)
    get my_contracts_path
    expect(response.body).not_to include("Doors are 7:30, the show is 8.")
  end

  it "is the contractor's alone: a person on the contract can't ask" do
    other = create(:user, password: password)
    other_person = create(:person, user: other)
    ContractPerson.create!(contract: contract, person: other_person)
    post handle_signin_path, params: { email_address: other.email_address, password: password }

    get my_contracts_path
    expect(response.body).not_to include("Request date/time change")

    expect do
      post my_ask_contract_date_path(contract), params: { show_id: show.id, kind: "cancel" }
    end.not_to change(ContractDateRequest, :count)
    expect(response).to redirect_to(my_contracts_path)
  end

  it "never reaches another contractor's contract or request" do
    their_person = create(:person, user: create(:user))
    their_contractor = create(:contractor, organization: org, person: their_person)
    theirs = create(:contract, :active, organization: org, production: production, contractor: their_contractor,
                                        contractor_name: their_contractor.name, contractor_email: their_contractor.email)

    expect do
      post my_ask_contract_date_path(theirs), params: { show_id: "new", proposed_at: (night + 2.days).strftime("%Y-%m-%dT%H:%M") }
    end.not_to change(ContractDateRequest, :count)
    expect(response).to redirect_to(my_contracts_path)

    mine = ContractDateRequests.ask!(contract: contract, user: user, show: show, kind: "cancel")
    delete my_contract_date_request_path(theirs, request_id: mine.id)
    expect(mine.reload.status).to eq("open")
  end
end
