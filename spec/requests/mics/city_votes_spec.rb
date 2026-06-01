# frozen_string_literal: true

require "rails_helper"

RSpec.describe "City votes", type: :request do
  describe "POST /mics/city_votes" do
    it "creates an anonymous vote with email" do
      expect {
        post mics_city_votes_path, params: { city: "Detroit", state: "mi", email: "fan@example.com" },
             headers: { "HTTP_REFERER" => mics_home_url }
      }.to change { CityVote.count }.by(1)

      vote = CityVote.last
      expect(vote.city).to eq("Detroit")
      expect(vote.state).to eq("MI") # normalized to upcase
      expect(vote.email).to eq("fan@example.com")
      expect(vote.user_id).to be_nil
    end

    it "creates a signed-in vote without email" do
      user = create(:user, password: "Password123!")
      post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }

      expect {
        post mics_city_votes_path, params: { city: "Portland", state: "OR", email: "ignored@example.com" },
             headers: { "HTTP_REFERER" => mics_home_url }
      }.to change { CityVote.count }.by(1)

      vote = CityVote.last
      expect(vote.user_id).to eq(user.id)
      expect(vote.email).to be_nil
    end

    it "rejects a vote with neither email nor signed-in user" do
      expect {
        post mics_city_votes_path, params: { city: "Nowhere", state: "ND" },
             headers: { "HTTP_REFERER" => mics_home_url }
      }.not_to(change { CityVote.count })
    end

    it "rejects a duplicate vote from the same signed-in user for the same city" do
      user = create(:user, password: "Password123!")
      post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }

      post mics_city_votes_path, params: { city: "Austin", state: "TX" },
           headers: { "HTTP_REFERER" => mics_home_url }
      expect(CityVote.count).to eq(1)

      expect {
        post mics_city_votes_path, params: { city: "Austin", state: "TX" },
             headers: { "HTTP_REFERER" => mics_home_url }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "CityVote.tallies" do
    it "returns top cities by raw vote count" do
      3.times { create(:city_vote, city: "Detroit", state: "MI") }
      2.times { create(:city_vote, city: "Portland", state: "OR") }
      create(:city_vote, city: "Austin", state: "TX")

      top = CityVote.tallies(limit: 5)
      expect(top.first).to eq([ [ "Detroit", "MI" ], 3 ])
      expect(top.second).to eq([ [ "Portland", "OR" ], 2 ])
      expect(top.size).to eq(3)
    end
  end

  describe "footer rendering" do
    it "shows top-voted cities on the homepage footer" do
      4.times { create(:city_vote, city: "Cleveland", state: "OH") }
      get mics_home_path
      expect(response.body).to include("Top requests")
      expect(response.body).to include("Cleveland")
    end
  end
end
