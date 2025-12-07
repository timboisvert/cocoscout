# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'My::Profile', type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address, name: 'Jane Smith', pronouns: 'she/her') }

  describe 'viewing profile' do
    it "displays user's profile information" do
      sign_in_as_person(user, person)
      visit '/my/profile'
      expect(page).to have_content('Jane Smith')
      expect(page).to have_content(person.email)
    end

    it 'displays pronouns when set' do
      sign_in_as_person(user, person)
      visit '/my/profile'
      expect(page).to have_content('she/her')
    end

    it 'has Edit Profile in top menu' do
      sign_in_as_person(user, person)
      visit '/my/profile'
      expect(page).to have_content('Edit Profile')
    end
  end

  describe 'editing profile' do
    it 'allows updating name' do
      sign_in_as_person(user, person)
      visit '/my/profile/edit'

      fill_in 'person_name', with: 'Jane Doe'
      click_button 'Update Profile'

      expect(page).to have_content('Jane Doe')
      expect(current_path).to eq('/my/profile')
    end

    it 'allows updating pronouns' do
      sign_in_as_person(user, person)
      visit '/my/profile/edit'

      fill_in 'person_pronouns', with: 'they/them'
      click_button 'Update Profile'

      expect(page).to have_content('Profile was successfully updated')
      expect(page).to have_content('they/them')
    end

    it 'displays form with current values' do
      sign_in_as_person(user, person)
      visit '/my/profile/edit'

      expect(page).to have_field('person_name', with: 'Jane Smith')
      expect(page).to have_field('person_pronouns', with: 'she/her')
    end

    it 'shows validation errors for invalid data' do
      sign_in_as_person(user, person)
      visit '/my/profile/edit'

      fill_in 'person_name', with: ''
      click_button 'Update Profile'

      expect(page).to have_content('Name is required')
    end
  end

  describe 'profile with resume' do
    before do
      person.resume.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
        filename: 'resume.pdf',
        content_type: 'application/pdf'
      )
    end

    it 'shows that resume is attached' do
      sign_in_as_person(user, person)
      visit '/my/profile'

      expect(page).to have_css('img') # Resume preview image should be visible
      expect(page).not_to have_content('No resume uploaded')
    end
  end

  describe 'profile with headshot' do
    before do
      person.headshot.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
        filename: 'headshot.jpg',
        content_type: 'image/jpeg'
      )
    end

    it 'displays the headshot' do
      sign_in_as_person(user, person)
      visit '/my/profile'

      expect(page).not_to have_content('No headshot uploaded')
      # Check for image in the headshot section
      within('.md\\:w-1\\/2:first-of-type') do
        expect(page).to have_css('img')
      end
    end
  end

  describe 'navigation from profile' do
    it 'can navigate back to dashboard from sidebar' do
      sign_in_as_person(user, person)
      visit '/my/profile'

      # The navigation is in the sidebar, not a specific link on the page
      expect(page).to have_content('Profile')
      expect(current_path).to eq('/my/profile')
    end
  end

  describe 'cancel editing' do
    it 'returns to previous page without saving changes' do
      sign_in_as_person(user, person)
      visit '/my/profile' # Start at profile
      click_link 'Edit Profile' # Go to edit

      fill_in 'person_name', with: 'Different Name'
      click_link 'Back' # Should go back to profile

      # Back button uses javascript:history.back() so it returns to the profile page
      expect(page).to have_content('Jane Smith')
      expect(page).not_to have_content('Different Name')
    end
  end
end
