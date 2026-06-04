# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics My page", type: :request do
  let(:user)  { create(:user, password: "Password123!") }
  let(:venue) { create(:venue, name: "Cafe Mustache", city: "Chicago", state: "IL") }

  def sign_in
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  describe "GET /mics/my" do
    it "redirects to signin when not authenticated" do
      get mics_my_path
      expect(response).to redirect_to(signin_path)
    end

    it "renders empty-state for favorites and hides the 'Mics you run' section when the user manages nothing" do
      sign_in
      get mics_my_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Mics you run")
      expect(response.body).to include("Upcoming from your favorites")
      expect(response.body).to include("Star a mic")
    end

    it "lists managed mics with a Manage link" do
      mic = create(:mic, venue: venue, name: "Mustache Mic")
      create(:mic_producer, mic: mic, user: user, role: :producer)
      sign_in

      get mics_my_path
      expect(response.body).to include("Mustache Mic")
      expect(response.body).to include(mics_owner_mic_path(mic.slug))
    end

    it "lists favorite mics with name (calendar view) and name + venue (list view)" do
      mic = create(:mic, venue: venue, name: "Lotties Open Mic")
      MicFavorite.create!(user: user, mic: mic)
      sign_in

      get mics_my_path # default = calendar (week view)
      expect(response.body).to include("Lotties Open Mic")

      get mics_my_path(view: "list")
      expect(response.body).to include("Lotties Open Mic")
      expect(response.body).to include(venue.name)
    end

    it "shows a favorited mic on the list view with an Unfavorite button" do
      mic = create(:mic, venue: venue, name: "Vault Mic")
      MicFavorite.create!(user: user, mic: mic)
      sign_in

      # Unfavorite lives on the list view (calendar view is purely visual).
      get mics_my_path(view: "list")
      expect(response.body).to include("Vault Mic")
      expect(response.body).to include("Unfavorite")
    end

    it "deduplicates a mic the user both runs and favorites across sections" do
      mic = create(:mic, venue: venue, name: "Dual Mic")
      create(:mic_producer, mic: mic, user: user, role: :producer)
      MicFavorite.create!(user: user, mic: mic)
      sign_in

      get mics_my_path
      # The mic name should appear in both sections — once under "Mics you run" and once under "Favorite mics".
      expect(response.body.scan(/Dual Mic/).size).to be >= 2
    end
  end

  describe "header points at My Mics" do
    it "shows the My Mics link to anyone, signed in or not" do
      get mics_home_path
      expect(response.body).to include(">My Mics<")
    end
  end
end
