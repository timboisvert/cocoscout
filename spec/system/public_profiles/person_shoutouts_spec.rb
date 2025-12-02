require 'rails_helper'

RSpec.describe "Public person profile shoutouts parity", type: :system do
  let!(:person_owner) { create(:user, password: "password123") }
  let!(:person) { create(:person, user: person_owner, email: person_owner.email_address, name: "Taylor Swift", public_key: "taylor-swift") }

  it "matches shoutouts UI/CTA like group profile (signed-out shows sign-in CTA)" do
    visit public_profile_path(person.public_key)

    expect(page).to have_content("Shoutouts")
    # Signed out -> sign-in CTA
    expect(page).to have_link("Sign in to Give a Shoutout", href: signin_path)

    # Sign in as another user
    other_user = create(:user, password: "password123")
    other_person = create(:person, user: other_user, email: other_user.email_address)

    sign_in_as_person(other_user, other_person)
    visit public_profile_path(person.public_key)

    # Signed in non-owner should be able to give shoutout
    expect(page).to have_link("Give #{person.name} a Shoutout", href: my_shoutouts_path(tab: "given", shoutee_type: "Person", shoutee_id: person.id))
  end
end
