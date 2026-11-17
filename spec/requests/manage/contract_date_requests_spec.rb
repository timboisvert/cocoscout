# frozen_string_literal: true

require "rails_helper"

# The contract page: a contractor's request about a date waits above the
# contract, answered by amending (Change dates opens on what they asked) or
# by keeping the date with a note.
RSpec.describe "Manage contract date requests", type: :request do
  let(:password) { "Password123!" }
  let!(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:asker) { create(:user) }
  let!(:asker_person) { create(:person, user: asker) }
  let!(:contractor) { create(:contractor, organization: org, person: asker_person) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let!(:location) { create(:location, organization: org) }
  let(:night) { 1.month.from_now.in_time_zone(org.time_zone).change(hour: 20, min: 0) }
  let!(:rental) do
    contract.space_rentals.create!(location: location, starts_at: night, ends_at: night + 2.hours, confirmed: true)
  end
  let!(:show) { production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental) }
  let(:asked) { night - 30.minutes }
  let!(:date_request) do
    ContractDateRequests.ask!(contract: contract, user: asker, show: show, kind: "move", proposed_at: asked, note: "We agreed on 7:30.")
  end

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "shows the request above the contract, with both answers" do
    get manage_contract_path(contract)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A request about a date")
    expect(response.body).to include("#{contractor.name} requests to move")
    expect(response.body).to include("We agreed on 7:30.")
    expect(response.body).to include(amend_dates_manage_contract_path(contract, request: date_request.id).gsub("&", "&amp;"))
    expect(response.body).to include("Keep 8:00 PM")
  end

  it "opens Change dates on what they asked for" do
    get amend_dates_manage_contract_path(contract, request: date_request.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-from-date-request")
    expect(response.body).to match(/name="dates\[#{rental.id}\]\[action\]" value="move" checked/)
    expect(response.body).to include(%(value="#{asked.strftime('%Y-%m-%dT%H:%M')}"))
  end

  it "leaves Change dates as it was without a request" do
    get amend_dates_manage_contract_path(contract)

    expect(response.body).not_to include("data-from-date-request")
    expect(response.body).to match(/name="dates\[#{rental.id}\]\[action\]" value="keep" checked/)
  end

  it "closes the request and notifies the asker when the date is moved as asked" do
    expect do
      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "move", starts_at: asked.strftime("%Y-%m-%dT%H:%M") } } }
    end.to change(asker.notifications, :count).by(1)

    expect(show.reload.date_and_time).to eq(asked)
    expect(date_request.reload).to have_attributes(status: "done", answered_by: owner)

    get manage_contract_path(contract)
    expect(response.body).not_to include("A request about a date")
  end

  it "keeps the date with a note, and notifies the asker" do
    expect do
      post keep_date_request_manage_contract_path(contract, request_id: date_request.id), params: { answer_note: "Doors are 7:30." }
    end.to change(asker.notifications, :count).by(1)

    expect(response).to redirect_to(manage_contract_path(contract))
    expect(date_request.reload).to have_attributes(status: "kept", answer_note: "Doors are 7:30.", answered_by: owner)
    expect(show.reload.date_and_time).to eq(night)
  end

  it "marks the contract on the Contracts list" do
    get manage_contracts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Date change requested")
  end

  it "never reaches another organization's request" do
    other_org = create(:organization, :pro)
    other_production = create(:production, organization: other_org, production_type: "third_party")
    their_person = create(:person, user: create(:user))
    their_contractor = create(:contractor, organization: other_org, person: their_person)
    theirs = create(:contract, :active, organization: other_org, production: other_production, contractor: their_contractor,
                                        contractor_name: their_contractor.name, contractor_email: their_contractor.email)
    their_request = theirs.date_requests.create!(organization: other_org, kind: "add", requested_by: their_person.user,
                                                 proposed_at: night + 3.days)

    post keep_date_request_manage_contract_path(theirs, request_id: their_request.id), params: { answer_note: "no" }
    expect(response).to have_http_status(:not_found)

    post keep_date_request_manage_contract_path(contract, request_id: their_request.id), params: { answer_note: "no" }
    expect(response).to have_http_status(:not_found)
    expect(their_request.reload.status).to eq("open")
  end
end
