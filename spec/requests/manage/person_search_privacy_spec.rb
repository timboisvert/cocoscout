# frozen_string_literal: true

require "rails_helper"

# People pickers search all of CocoScout, but only the organization's own
# people show their email (Tim, 2026-10-12). Everyone else is found by name,
# profile key or exact email, never part of an email.
RSpec.describe "People pickers keep outsiders' emails private", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:outsider) { create(:person, name: "Dana Outsider", email: "dana.private@example.com") }
  let!(:member) { create(:person, name: "Mo Member", email: "mo.member@example.com").tap { |p| org.people << p } }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "finds outsiders by name without their email, by exact email with it, never by part of it" do
    get search_for_invite_manage_people_path, params: { q: "Dana" }
    expect(response.body).to include("Dana Outsider")
    expect(response.body).not_to include("dana.private@example.com")

    get search_for_invite_manage_people_path, params: { q: "private" }
    expect(response.body).not_to include("Dana Outsider")

    get search_for_invite_manage_people_path, params: { q: "Dana.Private@example.com" }
    expect(response.body).to include("Dana Outsider", "dana.private@example.com")
  end

  it "still shows the organization's own people's emails, found by any part of them" do
    get search_for_invite_manage_people_path, params: { q: "mo.mem" }
    expect(response.body).to include("Mo Member", "mo.member@example.com")
  end

  it "keeps outsiders' emails out of the door and team pickers" do
    outsider.update!(user: create(:user, email_address: "dana.private@example.com"))
    member.update!(user: create(:user, email_address: "mo.member@example.com"))

    get manage_ticketing_door_search_path, params: { q: "Dana" }
    expect(response.body).to include("Dana Outsider")
    expect(response.body).not_to include("dana.private@example.com")

    get manage_ticketing_door_search_path, params: { q: "Mo M" }
    expect(response.body).to include("mo.member@example.com")

    get search_manage_team_index_path, params: { q: "Dana" }
    expect(response.body).to include("Dana Outsider")
    expect(response.body).not_to include("dana.private@example.com")
  end

  it "invites someone picked from outside the organization at their own address" do
    expect {
      post invite_manage_team_index_path, params: { team_invitation: { person_id: outsider.id, email: "" } }
    }.to change(TeamInvitation, :count).by(1)
    expect(TeamInvitation.last).to have_attributes(email: "dana.private@example.com", organization_id: org.id)
  end

  it "adds someone picked from outside the organization without needing their email" do
    expect {
      post manage_people_path, params: { selected_profile_ids: [ outsider.id ], person: { name: "Dana Outsider", email: "" } }
    }.to change(PersonInvitation, :count).by(1)
    expect(PersonInvitation.last.email).to eq("dana.private@example.com")
  end
end
