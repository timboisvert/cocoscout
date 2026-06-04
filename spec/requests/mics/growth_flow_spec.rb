# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics growth flow", type: :request do
  let(:user)  { create(:user, password: "Password123!") }
  let(:venue) { create(:venue, name: "The Comedy Vault", city: "Chicago", state: "IL") }
  let!(:mic)  { create(:mic, venue: venue, name: "Vault Mic") }

  def sign_in(u = user)
    post handle_signin_path, params: { email_address: u.email_address, password: "Password123!" }
  end

  describe "favorites" do
    before { sign_in }

    it "toggles a favorite on and off" do
      expect {
        post mics_favorite_path(mic.slug)
      }.to change { MicFavorite.count }.by(1)

      expect {
        post mics_favorite_path(mic.slug)
      }.to change { MicFavorite.count }.by(-1)
    end

    it "lists favorites" do
      MicFavorite.create!(user: user, mic: mic)
      get mics_favorites_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vault Mic")
    end
  end

  describe "alerts" do
    before { sign_in }

    it "toggles an alert on and off" do
      expect {
        post mics_alert_path(mic.slug)
      }.to change { MicSignupAlert.count }.by(1)

      alert = MicSignupAlert.last
      expect(alert.user).to eq(user)
      expect(alert.lead_time_minutes).to eq(5)

      expect {
        post mics_alert_path(mic.slug)
      }.to change { MicSignupAlert.count }.by(-1)
    end
  end

  describe "JSON API" do
    it "returns mics by city" do
      get "/mics/chicago-il.json"
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["city"]).to eq("Chicago")
      expect(data["mics"].first["name"]).to eq("Vault Mic")
    end

    it "returns a single mic" do
      get "/mics/m/#{mic.slug}.json"
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["slug"]).to eq(mic.slug)
      expect(data["venue"]["city"]).to eq("Chicago")
      expect(data["next_occurrences"]).to be_an(Array)
    end
  end

  describe "migration wizard" do
    before do
      create(:mic_owner, mic: mic, user: user, role: :owner)
      sign_in
    end

    it "shows the migrate page" do
      get mics_owner_migrate_path(mic.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Migrate")
    end

    it "links mic to a new production end-to-end" do
      expect {
        post mics_owner_perform_migrate_path(mic.slug)
      }.to change { Production.count }.by(1).and change { SignUpForm.count }.by(1)

      mic.reload
      expect(mic.production_id).not_to be_nil
      expect(mic.production.shows.where(event_type: :open_mic)).to be_present
      form = mic.production.sign_up_forms.first
      expect(form.event_type_filter).to include("open_mic")
      expect(form.active).to be(true)
      expect(mic.mic_edits.where(field: "production_id").exists?).to be(true)
    end
  end
end
