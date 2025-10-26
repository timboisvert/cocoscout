require 'rails_helper'

describe "Accept team invitation", type: :system do
  let!(:production_company) { create(:production_company) }
  let!(:team_invitation) { create(:team_invitation, production_company: production_company, email: "invitee@example.com") }

  it "allows a new user to accept an invitation and set a password" do
    visit "/manage/team_invitations/accept/#{team_invitation.token}"
    fill_in "password", with: "password123"
    click_button "Join #{production_company.name}"
    # After joining, user is redirected to add a production
    expect(page).to have_content("Add a Production")
  end
end
