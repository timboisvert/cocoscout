# frozen_string_literal: true

require "rails_helper"

# My → Productions, one production: a Tickets card with the production's
# link for sharing (Tim, 2026-10-16), for everyone in its talent pool when
# Who sees sales says so. Nothing per date here; each show's page has its own.
RSpec.describe "My production page: Tickets", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let!(:listing) { create(:ticket_listing, organization: org, show: show) }
  let(:performer) { create(:user, password: password) }
  let!(:person) { create(:person, user: performer, name: "Jamie Cruz").tap { |p| performer.update!(default_person: p) } }
  let(:profile) { TicketingProfile.for(org) }

  before do
    profile.update!(enabled: true)
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    post handle_signin_path, params: { email_address: performer.email_address, password: password }
  end

  it "shows the production's link, not a date's, and no QR" do
    get my_production_path(production)
    expect(response).to have_http_status(:ok)
    code = ShortLink.canonical_for!(production).code
    expect(response.body).to include("data-tickets-card", "/t/#{code}", "The production's link")
    expect(response.body).not_to include("/t/#{code}/#{ShortLink.date_suffix(show)}", "qr-code", "sold")
  end

  it "keeps it off the page when only the cast of each date sees sales, or nobody, or the box office is closed" do
    profile.update!(cast_sales: "show_cast")
    get my_production_path(production)
    expect(response.body).not_to include("data-tickets-card")

    profile.update!(cast_sales: "production_cast", enabled: false)
    get my_production_path(production)
    expect(response.body).not_to include("data-tickets-card")
  end
end
