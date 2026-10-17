# frozen_string_literal: true

require "rails_helper"

# The contract wizard's People step (Tim, 2026-10-16 as Team; 2026-10-17
# contract people, docs/contract_people_plan.md): the people on the
# contractor's side, staged on the draft and put on the contract the moment
# it's activated (Contract#apply_draft_people!, ContractPeopleAdder). They
# get the contractor's visibility on My and never a production permission.
# The contract's signer is suggested first.
RSpec.describe "Contract wizard: People step", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let(:clay) { create(:user, email_address: "clay@example.com", password: password) }
  let!(:clay_person) { create(:person, user: clay, name: "Clay Smith", email: "clay@example.com").tap { |p| clay.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: org, name: "Clay Smith Presents", email: "clay@example.com", person: clay_person) }
  let!(:contract) do
    create(:contract, organization: org, contractor: contractor, contractor_name: contractor.name, contractor_email: contractor.email,
                      production_name: "Stargazers", status: :draft, wizard_step: 7,
                      contract_start_date: Date.current, contract_end_date: Date.current + 7.days,
                      draft_data: { "bookings" => [ { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601, "ends_at" => (1.day.from_now + 2.hours).iso8601 } ] })
  end
  let(:priya) { create(:user, email_address: "priya@example.com", password: password) }
  let!(:priya_person) { create(:person, user: priya, name: "Priya Nair", email: "priya@example.com").tap { |p| priya.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "comes after About and before Schedule, suggesting the contract's signer" do
    post manage_signing_contract_wizard_path(contract), params: { signing_mode: "offline" }
    expect(response).to redirect_to(manage_people_contract_wizard_path(contract))

    get manage_people_contract_wizard_path(contract)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Who's on this contract", "Clay Smith", "From the contract", "Signs this contract for Clay Smith Presents",
                                     "Who else is on this contract?", "Add to the contract", "Next: Schedule", ">People<")
    expect(response.body).not_to include("Production team", "Manager", "Viewer")
    expect(contract.reload.draft_data["people"]).to eq([ { "user_id" => clay.id, "name" => "Clay Smith", "suggested" => true } ])

    post manage_people_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_bookings_contract_wizard_path(contract))
    get manage_bookings_contract_wizard_path(contract)
    expect(response.body).to include(manage_people_contract_wizard_path(contract))
  end

  it "suggests an invitation when the signer has no account" do
    contractor.update!(person: nil, email: "sam@brightlights.org")
    contract.update!(contractor_email: "sam@brightlights.org")
    get manage_people_contract_wizard_path(contract)
    expect(response.body).to include("sam@brightlights.org", "Will be invited by email", "From the contract")
    expect(contract.reload.draft_data["people"].first).to include("email" => "sam@brightlights.org", "suggested" => true)
  end

  it "adds someone found by search, invites someone by email, removes, and lists them on Review" do
    get manage_people_contract_wizard_path(contract)

    post manage_people_members_contract_wizard_path(contract), params: { person_id: priya_person.id }
    expect(response).to redirect_to(manage_people_contract_wizard_path(contract))
    expect(flash[:notice]).to eq("Priya Nair is on the contract.")

    post manage_people_members_contract_wizard_path(contract), params: { email: "Sam@BrightLights.org", name: "Sam" }
    people = contract.reload.draft_data["people"]
    expect(people.map { |m| m.slice("user_id", "email", "name") }).to eq([
      { "user_id" => clay.id, "name" => "Clay Smith" },
      { "user_id" => priya.id, "name" => "Priya Nair" },
      { "email" => "sam@brightlights.org", "name" => "Sam" }
    ])

    get manage_people_contract_wizard_path(contract)
    expect(response.body).to include("Priya Nair", "On CocoScout", "Sam", "Will be invited by email")
    expect(response.body).not_to include("priya@example.com")

    get manage_review_contract_wizard_path(contract)
    expect(response.body).to include("On this contract (3)", "Clay Smith", "Priya Nair", "Sam", "Will be invited by email", "From the contract", manage_people_contract_wizard_path(contract))

    delete manage_people_members_contract_wizard_path(contract), params: { user_id: priya.id }
    delete manage_people_members_contract_wizard_path(contract), params: { email: "sam@brightlights.org" }
    expect(contract.reload.draft_data["people"].map { |m| m["name"] }).to eq([ "Clay Smith" ])

    post manage_people_members_contract_wizard_path(contract), params: { email: "not an email" }
    expect(flash[:alert]).to eq("Pick someone, or enter their name and email.")
  end

  it "puts them on the contract when it's activated, never on the production team, and a bad entry never blocks it" do
    # A draft from before 2026-10-17, staged under "team" with roles, counts the same.
    contract.update!(draft_data: contract.draft_data.merge("team" => [
      { "user_id" => clay.id, "name" => "Clay Smith", "role" => "manager", "suggested" => true },
      { "user_id" => priya.id, "name" => "Priya Nair", "role" => "viewer" },
      { "email" => "sam@brightlights.org", "name" => "Sam", "role" => "viewer" },
      { "user_id" => 0, "name" => "Gone", "role" => "manager" }
    ]))

    expect { post manage_activate_contract_wizard_path(contract) }.to have_enqueued_mail(Manage::TeamMailer, :contract_invite)
    expect(response).to redirect_to(manage_contract_path(contract))
    production = contract.reload.production
    expect(production.name).to eq("Stargazers")
    # Clay is the contractor's own person: on the contract already, not a row of his own.
    expect(contract.contract_people.map(&:person)).to eq([ priya_person ])
    expect(ProductionPermission.where(production: production)).to be_empty
    expect(OrganizationRole.where(user: [ clay, priya ], organization: org)).to be_empty
    invitation = TeamInvitation.find_by(email: "sam@brightlights.org", contract: contract)
    expect(invitation.production_id).to be_nil

    # Accepting makes a contract person who lands on My Contracts: no role in the organization, no production permission.
    get signout_path
    post do_accept_manage_team_invitations_path(invitation.token), params: { password: password }
    expect(response).to redirect_to(my_contracts_path)
    sam = User.find_by(email_address: "sam@brightlights.org")
    expect(contract.contract_people.joins(:person).where(people: { user_id: sam.id })).to exist
    expect(OrganizationRole.where(user: sam)).to be_empty
    expect(ProductionPermission.where(user: sam)).to be_empty
    expect(invitation.reload.accepted_at).to be_present
  end
end
