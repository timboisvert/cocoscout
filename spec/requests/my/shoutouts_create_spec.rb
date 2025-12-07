# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'My::Shoutouts#create', type: :request do
  it 'blocks creating a shoutout for a group the current user belongs to' do
    user = create(:user)
    person = create(:person, user: user, email: user.email_address)

    group = create(:group)
    group.group_memberships.create!(person: person, permission_level: :view)

    # Sign in the user via the real signin flow to set cookies
    post handle_signin_path, params: { email_address: user.email_address, password: 'password123' }
    follow_redirect!

    expect do
      post my_create_shoutout_path, params: { shoutee_type: 'Group', shoutee_id: group.id, content: "You're great" }
    end.not_to change(Shoutout, :count)

    expect(response).to redirect_to(my_shoutouts_path(tab: 'given'))
    follow_redirect!
    # Ensure no shoutout created
    expect(Shoutout.where(shoutee: group).count).to eq(0)
  end
end
