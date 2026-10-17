# frozen_string_literal: true

require "rails_helper"

# The contract wizard's Team step (Tim, 2026-10-16): the production's team,
# staged on the draft and added or invited the moment the contract is
# activated (Contract#apply_draft_team!, ProductionTeamAdder). The
# contract's signer is suggested first, as a manager.
RSpec.describe "Contract wizard: Team step", type: :request do
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

  it "comes after About and before Schedule, suggesting the contract's signer as a manager" do
    post manage_signing_contract_wizard_path(contract), params: { signing_mode: "offline" }
    expect(response).to redirect_to(manage_team_contract_wizard_path(contract))

    get manage_team_contract_wizard_path(contract)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Production team", "Clay Smith", "From the contract", "Signs this contract for Clay Smith Presents",
                                     "Who else is on the team?", "Add to the team", "Next: Schedule", ">Team<")
    expect(response.body).not_to include("coustard-regular\">Production team")
    expect(contract.reload.draft_data["team"]).to eq([ { "user_id" => clay.id, "name" => "Clay Smith", "role" => "manager", "suggested" => true } ])

    post manage_team_contract_wizard_path(contract)
    expect(response).to redirect_to(manage_bookings_contract_wizard_path(contract))
    get manage_bookings_contract_wizard_path(contract)
    expect(response.body).to include(manage_team_contract_wizard_path(contract))
  end

  it "suggests an invitation when the signer has no account" do
    contractor.update!(person: nil, email: "sam@brightlights.org")
    contract.update!(contractor_email: "sam@brightlights.org")
    get manage_team_contract_wizard_path(contract)
    expect(response.body).to include("sam@brightlights.org", "Will be invited by email", "From the contract")
    expect(contract.reload.draft_data["team"].first).to include("email" => "sam@brightlights.org", "role" => "manager", "suggested" => true)
  end

  it "adds someone found by search, invites someone by email, removes, and lists them on Review" do
    get manage_team_contract_wizard_path(contract)

    post manage_team_members_contract_wizard_path(contract), params: { person_id: priya_person.id, role: "viewer" }
    expect(response).to redirect_to(manage_team_contract_wizard_path(contract))
    expect(flash[:notice]).to eq("Priya Nair is on the team.")

    post manage_team_members_contract_wizard_path(contract), params: { email: "Sam@BrightLights.org", name: "Sam", role: "manager" }
    team = contract.reload.draft_data["team"]
    expect(team.map { |m| m.slice("user_id", "email", "name", "role") }).to eq([
      { "user_id" => clay.id, "name" => "Clay Smith", "role" => "manager" },
      { "user_id" => priya.id, "name" => "Priya Nair", "role" => "viewer" },
      { "email" => "sam@brightlights.org", "name" => "Sam", "role" => "manager" }
    ])

    get manage_team_contract_wizard_path(contract)
    expect(response.body).to include("Priya Nair", "On CocoScout", "Sam", "Will be invited by email")
    expect(response.body).not_to include("priya@example.com")

    get manage_review_contract_wizard_path(contract)
    expect(response.body).to include("Production team (3)", "Clay Smith", "Priya Nair", "Sam", "Will be invited by email", "From the contract", manage_team_contract_wizard_path(contract))

    delete manage_team_members_contract_wizard_path(contract), params: { user_id: priya.id }
    delete manage_team_members_contract_wizard_path(contract), params: { email: "sam@brightlights.org" }
    expect(contract.reload.draft_data["team"].map { |m| m["name"] }).to eq([ "Clay Smith" ])

    post manage_team_members_contract_wizard_path(contract), params: { email: "not an email", role: "manager" }
    expect(flash[:alert]).to eq("Pick someone, or enter their name and email.")
  end

  it "adds and invites the team when the contract is activated, and a bad entry never blocks it" do
    contract.update!(draft_data: contract.draft_data.merge("team" => [
      { "user_id" => clay.id, "name" => "Clay Smith", "role" => "manager", "suggested" => true },
      { "user_id" => priya.id, "name" => "Priya Nair", "role" => "viewer" },
      { "email" => "sam@brightlights.org", "name" => "Sam", "role" => "manager" },
      { "user_id" => 0, "name" => "Gone", "role" => "manager" }
    ]))

    expect { post manage_activate_contract_wizard_path(contract) }.to have_enqueued_mail(Manage::TeamMailer, :production_invite)
    expect(response).to redirect_to(manage_contract_path(contract))
    production = contract.reload.production
    expect(production.name).to eq("Stargazers")
    expect(ProductionPermission.find_by(user: clay, production: production).role).to eq("manager")
    expect(ProductionPermission.find_by(user: priya, production: production).role).to eq("viewer")
    expect(OrganizationRole.find_by(user: clay, organization: org).company_role).to eq("member")
    invitation = TeamInvitation.find_by(email: "sam@brightlights.org", production: production)
    expect(invitation.invitation_role).to eq("manager")

    # Accepting the invitation makes a member of the organization, not a viewer of all of it.
    get signout_path
    post do_accept_manage_team_invitations_path(invitation.token), params: { password: password }
    sam = User.find_by(email_address: "sam@brightlights.org")
    expect(OrganizationRole.find_by(user: sam, organization: org).company_role).to eq("member")
    expect(ProductionPermission.find_by(user: sam, production: production).role).to eq("manager")
  end
end
