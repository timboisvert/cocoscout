# frozen_string_literal: true

require 'rails_helper'

describe 'Accept person invitation', type: :system do
  let!(:organization) { create(:organization) }
  let!(:person_invitation) { create(:person_invitation, organization: organization, email: 'talent@example.com') }

  it 'allows a new user to accept an invitation and set a password' do
    visit "/manage/person_invitations/accept/#{person_invitation.token}"

    expect(page).to have_content(organization.name)
    expect(page).to have_content(person_invitation.email)

    fill_in 'password', with: 'password123'
    click_button 'Join CocoScout'

    # Wait for redirect after form submission
    expect(page).not_to have_content('Create your account', wait: 10)

    # Verify the user and person were created properly
    user = User.find_by(email_address: person_invitation.email.downcase)
    expect(user).to be_present
    expect(user.authenticate('password123')).to be_truthy

    person = Person.find_by(email: person_invitation.email.downcase)
    expect(person).to be_present
    expect(person.user).to eq(user)
    expect(person.organizations).to include(organization)

    # Verify they're signed in and redirected appropriately
    expect([ manage_people_path, my_dashboard_path ]).to include(current_path)
  end
end
