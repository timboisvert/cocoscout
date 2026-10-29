# frozen_string_literal: true

require "rails_helper"

# A day with staffing and no show (a private party that isn't a show in
# CocoScout) still gets its row on Home, desktop and phone, and goes to
# that day on Scheduling (Tim, 2026-10-29). Pro managers only.
RSpec.describe "Home, a staffing-only day", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Laugh-Along, Live!") }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:thursday) { week_start + 3 }
  let(:sunday) { week_start + 6 }
  let!(:thu_show) { create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 20), duration_minutes: 90) }
  let(:bartender) { create(:house_role, organization: org, name: "Bartender", role_type: :house) }
  let(:gus) { create(:person, name: "Gus Lee") }
  let!(:party_shift) do
    create(:shift, organization: org, house_role: bartender, required_count: 2,
                   starts_at: sunday.in_time_zone.change(hour: 14), ends_at: sunday.in_time_zone.change(hour: 19))
  end

  before do
    org.people << gus
    party_shift.shift_assignments.create!(person: gus)
  end

  def page(user: owner, **params)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path(**params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "opens the day on the week with a staffing row that goes to Scheduling" do
    doc = page(week_start: week_start.to_s)
    grid = doc.at_css("[data-home-week]")
    expect(grid.at_css("[data-day-header='#{sunday.iso8601}']").text).to include("Staffing only")
    row = grid.at_css("[data-day-column='#{sunday.iso8601}'] [data-home-staffing-day='#{sunday.iso8601}']")
    expect(row["href"]).to eq(manage_staffing_scheduling_path(day: sunday.iso8601))
    expect(row.text).to include("2:00", "Staffing")
    chip = row.at_css("[data-chip='staffing']")
    expect(chip["data-tone"]).to eq("warn")
    expect(chip.text).to include("1/2")
    # A show day keeps its show rows and no staffing row; an empty day stays a sliver.
    expect(grid.at_css("[data-day-column='#{thursday.iso8601}'] [data-home-staffing-day]")).to be_nil
    expect(grid.at_css("[data-day-column='#{week_start.iso8601}']")).to be_nil
  end

  it "shows the day on a phone, worded, with who's on" do
    doc = page(day: sunday.iso8601)
    day = doc.at_css("[data-home-day='#{sunday.iso8601}']")
    expect(day.text).to include("Staffing only", "1 shift")
    row = day.at_css("[data-home-staffing-day='#{sunday.iso8601}']")
    expect(row.text).to include("Staffing · Bartender", "until 7:00 PM", "1 of 2 staffed · 1 open", "Gus Lee")
    expect(day.text).not_to include("Nothing on Sunday")
    expect(day.at_css("[data-strip-day='#{sunday.iso8601}']")).to be_present
  end

  it "counts a shift tied to a rental on the rental's day" do
    party_shift.update!(starts_at: (sunday - 1).in_time_zone.change(hour: 23), ends_at: sunday.in_time_zone.change(hour: 3),
                        source: create(:space_rental, contract: create(:contract, organization: org), starts_at: sunday.in_time_zone.change(hour: 0),
                                                                    ends_at: sunday.in_time_zone.change(hour: 4)))
    doc = page(week_start: week_start.to_s)
    expect(doc.at_css("[data-day-column='#{sunday.iso8601}'] [data-home-staffing-day='#{sunday.iso8601}']")).to be_present
  end

  it "shows nothing of it to someone who isn't a manager" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org)
    doc = page(user: viewer, week_start: week_start.to_s)
    expect(doc.at_css("[data-home-staffing-day]")).to be_nil
    expect(doc.at_css("[data-day-column='#{sunday.iso8601}']")).to be_nil
  end

  it "shows nothing of it on the Producer plan" do
    org.update!(comped_indefinitely: false)
    doc = page(week_start: week_start.to_s)
    expect(doc.at_css("[data-home-staffing-day]")).to be_nil
    expect(doc.at_css("[data-day-column='#{sunday.iso8601}']")).to be_nil
  end
end
