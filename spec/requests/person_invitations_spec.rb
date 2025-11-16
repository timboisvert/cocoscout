require 'rails_helper'

RSpec.describe "PersonInvitations", type: :request do
  let!(:organization) { create(:organization) }
  let!(:person_invitation) { create(:person_invitation, organization: organization, email: "talent@example.com") }

  describe "GET /manage/person_invitations/accept/:token" do
    it "displays the invitation accept form" do
      get "/manage/person_invitations/accept/#{person_invitation.token}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(organization.name)
      expect(response.body).to include(person_invitation.email)
    end
  end

  describe "POST /manage/person_invitations/accept/:token" do
    it "creates a user, person, and accepts the invitation" do
      expect {
        post "/manage/person_invitations/accept/#{person_invitation.token}", params: { password: "password123" }
      }.to change(User, :count).by(1)
        .and change(Person, :count).by(1)

      # Verify the user was created with correct email
      user = User.find_by(email_address: person_invitation.email.downcase)
      expect(user).to be_present
      expect(user.authenticate("password123")).to be_truthy

      # Verify the person was created and linked
      person = Person.find_by(email: person_invitation.email.downcase)
      expect(person).to be_present
      expect(person.user).to eq(user)
      expect(person.organizations).to include(organization)

      # Verify the invitation was marked as accepted
      person_invitation.reload
      expect(person_invitation.accepted_at).to be_present

      # Verify redirect to manage people path
      expect(response).to redirect_to(manage_people_path)
    end
  end
end
