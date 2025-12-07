# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public group profile shoutouts', type: :system do
  let!(:group) { create(:group, name: 'Theatre Troupe', public_key: 'theatre-troupe') }

  it 'shows sign-in CTA when user is not signed in' do
    visit public_profile_path(group.public_key)

    expect(page).to have_content('Shoutouts')
    expect(page).to have_link('Sign in to Give a Shoutout', href: signin_path)
  end

  it 'shows Give a Shoutout for signed-in user who is not a member' do
    user = create(:user, password: 'password123')
    person = create(:person, user: user, email: user.email_address)

    sign_in_as_person(user, person)
    visit public_profile_path(group.public_key)

    expect(page).to have_link("Give #{group.name} a Shoutout",
                              href: my_shoutouts_path(tab: 'given', shoutee_type: 'Group', shoutee_id: group.id))
  end

  it 'does not show Give a Shoutout if the current user is a member of the group' do
    user = create(:user, password: 'password123')
    person = create(:person, user: user, email: user.email_address)

    # make the person a member
    group.group_memberships.create!(person: person, permission_level: :view)

    sign_in_as_person(user, person)
    visit public_profile_path(group.public_key)

    expect(page).not_to have_button("Give #{group.name} a Shoutout")
    expect(page).not_to have_link(my_shoutouts_path(tab: 'given', shoutee_type: 'Group', shoutee_id: group.id))
  end
end
