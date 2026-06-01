# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics producer flow", type: :request do
  let(:user)  { create(:user, password: "Password123!") }
  let(:venue) { create(:venue, name: "Beat Kitchen", city: "Chicago", state: "IL") }
  let!(:mic)  { create(:mic, venue: venue, name: "Beat Kitchen Mic") }

  def sign_in(u = user)
    post handle_signin_path, params: { email_address: u.email_address, password: "Password123!" }
  end

  describe "GET /mics/submit" do
    it "redirects unauthenticated to signin" do
      get mics_submit_path
      expect(response).to redirect_to(signin_path)
    end

    it "renders the form when signed in" do
      sign_in
      get mics_submit_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Submit a mic")
    end
  end

  describe "POST /mics/submit" do
    before { sign_in }

    it "creates a pending mic and a venue, capturing bucket_draw separately from the channel" do
      post mics_create_submission_path, params: {
        venue: { name: "Replay Lincoln Park", address1: "2833 N Sheffield", city: "Chicago", state: "IL" },
        mic:   { name: "Replay Mic", format: "standup", day_of_week: 3, starts_local_time: "20:00",
                 signup_method: "in_person", bucket_draw: "1", signup_opens_at_text: "Bucket at 7:30",
                 cost: "free", blurb: "Wednesday weekly." }
      }
      mic = Mic.find_by(name: "Replay Mic")
      expect(mic).not_to be_nil
      expect(mic.pending).to be(true)
      expect(mic.signup_method).to eq("in_person")
      expect(mic.bucket_draw).to be(true)
      expect(response).to redirect_to(mics_detail_path(mic.slug))
    end
  end

  describe "GET /mics/m/:slug/claim" do
    it "renders the claim form for a signed-in user" do
      sign_in
      get mics_claim_path(mic.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Claim")
    end
  end

  describe "POST /mics/m/:slug/claim" do
    before { sign_in }

    it "files a pending claim" do
      expect {
        post mics_create_claim_path(mic.slug), params: {
          mic_claim: { role: "producer", proof: { email: "anyone@example.com" } }
        }
      }.to change { MicClaim.count }.by(1)
      claim = MicClaim.last
      expect(claim.status).to eq("pending")
      expect(claim.claimant).to eq(user)
    end
  end

  describe "GET /mics/producer when user manages a mic" do
    it "redirects to /mics/my (unified) and that page lists the user's mics" do
      create(:mic_producer, mic: mic, user: user)
      sign_in
      get mics_producer_path
      expect(response).to redirect_to(mics_my_path)
      follow_redirect!
      expect(response.body).to include("Beat Kitchen Mic")
    end

    it "refuses producer/:slug for non-producers" do
      sign_in
      get mics_producer_mic_path(mic.slug)
      expect(response).to have_http_status(:forbidden)
    end

    it "allows producer to update their mic" do
      create(:mic_producer, mic: mic, user: user)
      sign_in
      patch mics_producer_mic_path(mic.slug), params: { mic: { blurb: "Refreshed copy." } }
      expect(response).to redirect_to(mics_producer_mic_path(mic.slug))
      expect(mic.reload.blurb).to eq("Refreshed copy.")
      expect(mic.mic_edits.where(field: "blurb").exists?).to be(true)
    end
  end

  describe "GET /mics/m/:slug/suggest" do
    it "renders the suggestion form without auth" do
      get mics_suggest_path(mic.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Suggest an edit")
    end

    it "creates a pending suggestion" do
      expect {
        post mics_create_suggestion_path(mic.slug), params: {
          mic_suggestion: { submitter_email: "fan@example.com", note: "Moved to Tuesdays." }
        }
      }.to change { MicSuggestion.count }.by(1)
    end
  end

  describe "POST /mics/m/:slug/challenge" do
    it "files a challenge" do
      sign_in
      expect {
        post mics_create_challenge_path(mic.slug), params: {
          mic_challenge: { reason: "I run this." }
        }
      }.to change { MicChallenge.count }.by(1)
      expect(MicChallenge.last.status).to eq("pending")
    end
  end
end
