# frozen_string_literal: true

require "rails_helper"

# A production's page in My.
RSpec.describe "A production's page in My", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:production) { create(:production) }

  before do
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  # On a phone the calendar lists this month on; with every date past it was
  # blank (Tim, 2026-10-13).
  it "says nothing is coming up when every date is in the past" do
    create(:show, production: production, date_and_time: Time.zone.local(2026, 8, 14, 20))
    travel_to Time.zone.local(2026, 10, 13, 12) do
      get my_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing coming up", "Friday, August 14, 2026")
    end
  end
end
