# frozen_string_literal: true

require "rails_helper"

# The profile's first-visit education is the profile_intro guide on the page
# itself — the old full-page welcome takeover (and its profile_welcomed_at
# redirect) is gone.
RSpec.describe "Profile intro guide", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }

  before do
    Person.create!(email: user.email_address, name: "Performer", user: user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "renders the profile page directly with the guide — no welcome redirect" do
    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-intro-guide="profile_intro"')
    expect(response.body).to include("Welcome to your profile")
  end

  it "hides the guide once dismissed, with a way back" do
    post guide_dismiss_path("profile_intro")
    get profile_path

    expect(response.body).not_to include('data-intro-guide="profile_intro"')
    expect(response.body).to include("Show it on the page")

    post guide_restore_path("profile_intro")
    get profile_path
    expect(response.body).to include('data-intro-guide="profile_intro"')
  end
end
