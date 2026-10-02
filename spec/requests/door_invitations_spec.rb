# frozen_string_literal: true

require "rails_helper"

# Accepting an invitation to work a theater's door: someone new makes an
# account, someone with one signs in, and either way lands on /door.
RSpec.describe "Door invitations", type: :request do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }
  let(:grant) { TicketingAccessGrant.invite!(organization: org, email: "sam@volunteer.example", name: "Sam Volunteer", level: "check_in", by: nil) }

  it "lets someone new make an account and start working the door" do
    token = grant.invitation_token
    get door_invitation_path(token: token)
    expect(response.body).to include("Stars &amp; Garters invited you to work the door", "Choose a password for your new CocoScout account")

    post door_invitation_accept_path(token: token), params: { password: "Password123!" }
    expect(response).to redirect_to(door_index_path)
    user = User.find_by!(email_address: "sam@volunteer.example")
    expect(user.person.name).to eq("Sam Volunteer")
    expect(grant.reload.attributes.slice("user_id", "invitation_token")).to eq("user_id" => user.id, "invitation_token" => nil)
    expect(TicketingDoorAccess.level_for(user, org)).to eq(:check_in)

    # Used once; the link doesn't work again.
    get door_invitation_path(token: token)
    expect(response).to have_http_status(:redirect)
  end

  it "asks someone with an account for their password" do
    user = create(:user, email_address: "sam@volunteer.example", password: "Password123!")
    get door_invitation_path(token: grant.invitation_token)
    expect(response.body).to include("Your CocoScout password", "Sign in and accept")

    post door_invitation_accept_path(token: grant.invitation_token), params: { password: "wrong" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("That password isn&#39;t right.")

    post door_invitation_accept_path(token: grant.invitation_token), params: { password: "Password123!" }
    expect(response).to redirect_to(door_index_path)
    expect(grant.reload.user).to eq(user)
  end

  it "won't take a withdrawn invitation" do
    token = grant.invitation_token
    grant.revoke!
    get door_invitation_path(token: token)
    expect(response).to redirect_to(signin_path)
  end
end
