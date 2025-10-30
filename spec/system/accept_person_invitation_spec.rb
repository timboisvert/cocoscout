require 'rails_helper'

describe "Accept person invitation", type: :system do
  let!(:production_company) { create(:production_company) }
  let!(:person_invitation) { create(:person_invitation, production_company: production_company, email: "talent@example.com") }

  it "allows a new user to accept an invitation and set a password" do
    visit "/manage/person_invitations/accept/#{person_invitation.token}"

    expect(page).to have_content("Join #{production_company.name}")
    expect(page).to have_content(person_invitation.email)

    fill_in "password", with: "password123"
    click_button "Join #{production_company.name}"

    # Verify the user and person were created properly
    user = User.find_by(email_address: person_invitation.email.downcase)
    expect(user).to be_present
    expect(user.authenticate("password123")).to be_truthy

    person = Person.find_by(email: person_invitation.email.downcase)
    expect(person).to be_present
    expect(person.user).to eq(user)
    expect(person.production_companies).to include(production_company)

    # User should have a role for the production company
    user_role = UserRole.find_by(user: user, production_company: production_company)
    expect(user_role).to be_present

    # Verify they're now signed in (the redirect may vary based on permissions)
    # The important part is that the invitation was accepted and they can access the system
    expect([ manage_people_path, my_dashboard_path ]).to include(current_path)
  end
end
