require 'rails_helper'

describe "Accept invitation", type: :system do
  let!(:production_company) { create(:production_company) }
  let!(:invitation) { create(:invitation, production_company: production_company, email: "invitee@example.com") }

  it "allows a new user to accept an invitation and set a password" do
    visit accept_invitations_path(token: invitation.token)
    fill_in "password", with: "password123"
    click_button "Join #{production_company.name}"
    expect(page).to have_content("Productions", wait: 5)
  end
end
