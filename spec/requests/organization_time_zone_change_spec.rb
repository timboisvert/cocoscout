# frozen_string_literal: true

require "rails_helper"

# Changing an organization's time zone (Tim, 2026-11-22): keep the clock moves
# every entered time so it reads the same in the new zone, date by date; keep
# the moment changes only the zone. Moments that happened never move.
RSpec.describe "Changing an organization's time zone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, owner: owner, name: "Stars & Garters", time_zone: "Central Time (US & Canada)") }
  let(:central) { ActiveSupport::TimeZone["Central Time (US & Canada)"] }
  let(:pacific) { ActiveSupport::TimeZone["Pacific Time (US & Canada)"] }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  # One date in summer and one in winter, so daylight saving is on each side.
  let!(:summer) { create(:show, production: production, date_and_time: central.local(2027, 7, 9, 20, 0)) }
  let!(:winter) { create(:show, production: production, date_and_time: central.local(2027, 1, 15, 19, 30)) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "keeps the clock: 8:00 PM stays 8:00 PM in the new zone, in summer and winter, and the zone changes" do
    created = summer.created_at
    OrganizationTimeZoneChange.apply!(org, to: pacific.name, keep: :clock)

    expect(summer.reload.date_and_time.in_time_zone(pacific).strftime("%b %-d %-l:%M %p")).to eq("Jul 9 8:00 PM")
    expect(winter.reload.date_and_time.in_time_zone(pacific).strftime("%b %-d %-l:%M %p")).to eq("Jan 15 7:30 PM")
    expect(summer.created_at).to eq(created)
    expect(org.reload.time_zone).to eq(pacific.name)
  end

  it "keeps the moment: nothing moves, only the zone" do
    moment = summer.date_and_time
    OrganizationTimeZoneChange.apply!(org, to: pacific.name, keep: :moment)
    expect(summer.reload.date_and_time).to eq(moment)
    expect(org.reload.time_zone).to eq(pacific.name)
  end

  it "sends a new zone through its own page, then applies the choice" do
    patch manage_organization_path(org), params: { organization: { name: "Stars and Garters", time_zone: pacific.name } }
    expect(response).to redirect_to(time_zone_manage_organization_path(org, to: pacific.name))
    expect(org.reload.name).to eq("Stars and Garters")
    expect(org.time_zone).to eq(central.name)

    get time_zone_manage_organization_path(org, to: pacific.name)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Keep the times as I entered them", "Keep the moments", "dates (2)", "Boylesque")

    post time_zone_manage_organization_path(org), params: { to: pacific.name, keep: "clock" }
    expect(response).to redirect_to(manage_organization_path(org))
    expect(org.reload.time_zone).to eq(pacific.name)
    expect(summer.reload.date_and_time.in_time_zone(pacific).hour).to eq(20)
  end

  it "changes the zone straight away when nothing is entered yet" do
    Show.where(production: production).delete_all
    patch manage_organization_path(org), params: { organization: { time_zone: pacific.name } }
    expect(response).to redirect_to(manage_organization_path(org))
    expect(org.reload.time_zone).to eq(pacific.name)
  end
end
