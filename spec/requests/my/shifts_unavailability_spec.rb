# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Shifts unavailability", type: :request do
  let(:user) { create(:user, password: "Password123!") }
  let!(:person) { create(:person, user: user) }

  def sign_in
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  before { sign_in }

  describe "POST /my/shifts/unavailability" do
    it "sets unavailability for a batch of dates" do
      dates = %w[2026-06-10 2026-06-11 2026-06-12]
      post my_create_shift_unavailability_path, params: { dates: dates, scope: "day_shifts" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be(true)
      expect(person.staff_unavailabilities.pluck(:date).map(&:to_s)).to match_array(dates)
      expect(person.staff_unavailabilities.pluck(:scope).uniq).to eq([ "day_shifts" ])
    end

    it "accepts a single date param" do
      post my_create_shift_unavailability_path, params: { date: "2026-06-15", scope: "all_day" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(person.staff_unavailabilities.find_by(date: "2026-06-15").scope).to eq("all_day")
    end

    it "updates the scope of an existing date instead of duplicating" do
      create(:staff_unavailability, person: person, date: Date.new(2026, 6, 20), scope: :all_day)
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-20" ], scope: "evening_shifts" }, as: :json

      expect(person.staff_unavailabilities.where(date: "2026-06-20").count).to eq(1)
      expect(person.staff_unavailabilities.find_by(date: "2026-06-20").scope).to eq("evening_shifts")
    end

    it "clears unavailability for the given dates" do
      create(:staff_unavailability, person: person, date: Date.new(2026, 6, 25))
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-25" ], scope: "clear" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(person.staff_unavailabilities.where(date: "2026-06-25")).to be_empty
    end

    it "rejects an invalid scope" do
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "bogus" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(person.staff_unavailabilities).to be_empty
    end

    it "rejects when no dates are given" do
      post my_create_shift_unavailability_path, params: { scope: "all_day" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "only ever touches the current user's own person" do
      other = create(:person)
      post my_create_shift_unavailability_path, params: { dates: [ "2026-06-10" ], scope: "all_day" }, as: :json
      expect(other.staff_unavailabilities).to be_empty
      expect(person.staff_unavailabilities.count).to eq(1)
    end
  end

  describe "GET /my/shifts" do
    it "renders and embeds existing unavailability entries" do
      create(:staff_unavailability, person: person, date: Date.current + 3.days, scope: :evening_shifts)
      get my_shifts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("evening_shifts")
    end
  end
end
