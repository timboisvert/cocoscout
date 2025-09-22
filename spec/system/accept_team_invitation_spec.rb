require 'rails_helper'

describe "Accept team invitation", type: :system do
  let!(:production_company) { create(:production_company) }
  let!(:team_invitation) { create(:team_invitation, production_company: production_company, email: "invitee@example.com") }

  it "allows a new user to accept an invitation and set a password" do
    visit accept_team_invitations_path(token: team_invitation.token)
    fill_in "Password", with: "password123"
    click_button "Continue"
    expect(page).to have_content("You have joined #{production_company.name}")
  end
end
