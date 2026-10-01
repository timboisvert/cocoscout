# frozen_string_literal: true

require "rails_helper"

# Ticketing settings → Door access: managers give staff, or anyone with a
# CocoScout account, Check in or Box office access to the door.
RSpec.describe "Manage ticketing door access", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }

  def user_with_person(name)
    user = create(:user)
    person = create(:person, name: name, email: user.email_address, user: user)
    user.update!(default_person: person)
    [ user, person ]
  end

  before do
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  it "lists staff with accounts to pick, and names the ones who can't be added yet" do
    _, sam = user_with_person("Sam Rivera")
    create(:organization_staff_member, organization: org, person: sam)
    create(:organization_staff_member, organization: org, person: create(:person, name: "Pat No-Account"))

    get manage_ticketing_settings_section_path(section: "door")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sam Rivera", "Not on CocoScout yet, so they can't be added: Pat No-Account")
  end

  it "gives door access to the staff ticked, at the level chosen" do
    sam_user, sam = user_with_person("Sam Rivera")
    lee_user, lee = user_with_person("Lee Park")
    members = [ sam, lee ].map { |person| create(:organization_staff_member, organization: org, person: person) }

    post manage_ticketing_door_access_path, params: { staff_member_ids: members.map(&:id), access_level: "box_office" }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "door"))
    expect(flash[:notice]).to eq("2 people can now work the box office at the door.")
    expect(org.ticketing_access_grants.active.pluck(:user_id, :access_level, :granted_by_id))
      .to contain_exactly([ sam_user.id, "box_office", superadmin.id ], [ lee_user.id, "box_office", superadmin.id ])
  end

  it "finds anyone on CocoScout and gives them access" do
    friend, friend_person = user_with_person("Jordan Friend")

    get manage_ticketing_door_search_path, params: { q: "jordan" }
    expect(response.body).to include("Jordan Friend", "Choose")
    get manage_ticketing_door_search_path, params: { q: "zzz" }
    expect(response.body).to include("They need a CocoScout account first")

    post manage_ticketing_door_access_path, params: { person_id: friend_person.id, access_level: "check_in" }
    expect(flash[:notice]).to eq("Jordan Friend can now check people in at the door.")
    expect(org.ticketing_access_grants.active.sole.user).to eq(friend)

    get manage_ticketing_door_search_path, params: { q: "jordan" }
    expect(response.body).to include("Has access")
  end

  it "skips managers, who always have the door" do
    post manage_ticketing_door_access_path, params: { person_id: create(:person, user: superadmin).id, access_level: "check_in" }
    expect(flash[:notice]).to include("already work the door")
    expect(org.ticketing_access_grants).to be_empty
  end

  it "changes a level and removes access, keeping the record" do
    user, = user_with_person("Sam Rivera")
    grant = org.ticketing_access_grants.create!(user: user, access_level: "check_in")

    patch manage_ticketing_door_access_grant_path(grant), params: { access_level: "box_office" }
    expect(grant.reload.access_level).to eq("box_office")

    delete manage_ticketing_door_access_grant_path(grant)
    expect(flash[:notice]).to eq("Sam Rivera can no longer work the door.")
    expect([ grant.reload.revoked?, grant.revoked_by ]).to eq([ true, superadmin ])
  end

  it "can't touch another theater's grants" do
    other = create(:organization, :pro)
    grant = other.ticketing_access_grants.create!(user: create(:user), access_level: "check_in")

    delete manage_ticketing_door_access_grant_path(grant)
    expect(response).to have_http_status(:not_found)
    patch manage_ticketing_door_access_grant_path(grant), params: { access_level: "box_office" }
    expect(response).to have_http_status(:not_found)
    expect(grant.reload.revoked?).to be(false)
  end

  it "only adds this theater's staff" do
    other = create(:organization, :pro)
    _, person = user_with_person("Elsewhere Staff")
    member = create(:organization_staff_member, organization: other, person: person)

    post manage_ticketing_door_access_path, params: { staff_member_ids: [ member.id ], access_level: "check_in" }
    expect(flash[:alert]).to eq("Choose someone to give door access to.")
    expect(TicketingAccessGrant.count).to eq(0)
  end
end
