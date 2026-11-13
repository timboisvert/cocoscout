# frozen_string_literal: true

require "rails_helper"

# A day of audition sessions shows on Home (Tim, 2026-11-12: a Saturday with
# nine sessions read "Nothing yet"). One row per audition cycle for the day,
# on the week and on the phone's day, going to the cycle's Sessions. Not a
# Pro feature: any organization's Home shows it.
RSpec.describe "Home, a day of auditions", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner, name: "Vocalize Arts") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Winter Cabaret") }
  let!(:cycle) { create(:audition_cycle, production: production) }
  let(:location) { create(:location, organization: org, name: "The Annoyance Theatre") }

  let(:week_start) { Date.current.beginning_of_week + 2.weeks }
  let(:saturday) { week_start + 5 }
  let!(:sessions) do
    [ [ 13, 0 ], [ 13, 15 ], [ 13, 30 ] ].map do |hour, min|
      starts = saturday.in_time_zone.change(hour: hour, min: min)
      create(:audition_session, audition_cycle: cycle, location: location, start_at: starts, end_at: starts + 15.minutes)
    end
  end

  def page(**params)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path(**params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "gives the day one row on the week, for all its sessions" do
    grid = page(week_start: week_start.to_s).at_css("[data-home-week]")
    expect(grid.at_css("[data-day-header='#{saturday.iso8601}']").text).to include("Auditions")
    rows = grid.css("[data-day-column='#{saturday.iso8601}'] [data-home-auditions]")
    expect(rows.size).to eq(1)
    expect(rows.first["href"]).to eq(manage_signups_auditions_cycle_sessions_path(production, cycle))
    expect(rows.first.text.squish).to include("1:00", "Auditions: Winter Cabaret", "3 sessions", "none booked")
  end

  it "shows it on the phone's day too" do
    day = page(day: saturday.iso8601).at_css("[data-home-day='#{saturday.iso8601}']")
    row = day.at_css("[data-home-auditions]")
    expect(row.text.squish).to include("Auditions: Winter Cabaret", "3 sessions · nobody booked yet", "The Annoyance Theatre")
    expect(day.text).not_to include("Nothing on")
  end

  it "leaves another organization's auditions off" do
    other = create(:production, organization: create(:organization), name: "Elsewhere")
    theirs = create(:audition_cycle, production: other)
    create(:audition_session, audition_cycle: theirs, location: create(:location, organization: other.organization),
                              start_at: saturday.in_time_zone.change(hour: 15))
    grid = page(week_start: week_start.to_s).at_css("[data-home-week]")
    expect(grid.text).not_to include("Elsewhere")
  end
end
