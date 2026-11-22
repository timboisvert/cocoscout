# frozen_string_literal: true

require "rails_helper"

# Invitation pages sent to an address that already has an account
# (InvitationSignIn). The account's owner proves it's theirs with its
# password, or by signing in with a code on the sign-in screen, which brings
# them straight back to accept with one tap. Before 2026-11-22 these pages
# required a password, which stranded everyone an organization had added who
# never chose one.
RSpec.describe "Invitations for an address that already has an account", type: :request do
  let(:org) { create(:organization, name: "Blue Room Theater") }
  let!(:user) { User.create_unclaimed!(email_address: "added@example.com") }
  let!(:person) { create(:person, email: "added@example.com", name: "Added Person", user: user) }

  # Through the sign-in screen with a code, from the page's own link.
  def sign_in_with_a_code_from(page_path)
    get code_link_on(page_path)
    post handle_signin_path, params: { step: "start", email_address: user.email_address }
    post handle_signin_path, params: { step: "code", code: emailed_code_for(user.email_address) }
  end

  def code_link_on(page_path)
    get page_path
    link = Nokogiri::HTML(response.body).css("a").find { |a| a.text.include?("Sign in with a code") }
    expect(link).to be_present
    link["href"]
  end

  describe "a team invitation" do
    let(:invitation) { create(:team_invitation, organization: org, email: user.email_address) }
    let(:page) { accept_manage_team_invitations_path(token: invitation.token) }

    it "comes back from the code signed in and joins with one tap, no password" do
      sign_in_with_a_code_from(page)
      expect(response).to redirect_to(page)

      follow_redirect!
      expect(response.body).to include("You&#39;re signed in as added@example.com", "Join Blue Room Theater")
      expect(response.body).not_to include('type="password"')

      post do_accept_manage_team_invitations_path(token: invitation.token)
      expect(response).to redirect_to(manage_path)
      expect(invitation.reload.accepted_at).to be_present
      expect(OrganizationRole.exists?(user: user, organization: org)).to be(true)
    end

    it "still refuses someone who is not signed in and has no right password" do
      post do_accept_manage_team_invitations_path(token: invitation.token), params: { password: "Guess123!" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.accepted_at).to be_nil
    end

    it "does not accept someone signed in to a different account" do
      other = create(:user, password: "Password123!")
      post handle_signin_path, params: { email_address: other.email_address, password: "Password123!" }

      post do_accept_manage_team_invitations_path(token: invitation.token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.accepted_at).to be_nil
    end
  end

  describe "a door invitation" do
    let(:org) { create(:organization, :pro, name: "Blue Room Theater") }
    let(:grant) { TicketingAccessGrant.invite!(organization: org, email: user.email_address, name: "Added Person", level: "check_in", by: nil) }

    it "comes back from the code signed in and accepts with one tap" do
      sign_in_with_a_code_from(door_invitation_path(token: grant.invitation_token))
      expect(response).to redirect_to(door_invitation_path(token: grant.invitation_token))

      post door_invitation_accept_path(token: grant.invitation_token)
      expect(response).to redirect_to(door_index_path)
      expect(grant.reload.user).to eq(user)
    end
  end
end
