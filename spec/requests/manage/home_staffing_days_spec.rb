# frozen_string_literal: true

require "rails_helper"

# A day with staffing and no show (a private party that isn't a show in
# CocoScout) still gets its row on Home, desktop and phone, and goes to
# that day on Scheduling (Tim, 2026-10-29). Roles for the whole night
# (bartender, house staff) get a row of their own too, named after them,
# never counted on one show (Tim, 2026-10-30). Pro managers only.
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
    expect(row.text).to include("2:00", "Bartender")
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
    expect(row.text).to include("Bartender", "until 7:00 PM", "1 of 2 staffed · 1 open", "Gus Lee")
    expect(day.text).not_to include("Nothing on Sunday")
    expect(day.at_css("[data-strip-day='#{sunday.iso8601}']")).to be_present
  end

  describe "a night of three shows" do
    let(:booth) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific) }
    let(:house_staff) { create(:house_role, organization: org, name: "House Staff", role_type: :house) }
    let(:fay) { create(:person, name: "Fay Lily") }
    let(:miles) { create(:person, name: "Miles Rowe") }
    let(:tess) { create(:person, name: "Tess Ng") }
    let(:other) { create(:production, organization: org, name: "Vampire Lesbians of Sodom") }
    let!(:seven) { create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 19), duration_minutes: 60) }
    let!(:eight) { create(:show, production: other, date_and_time: thursday.in_time_zone.change(hour: 20, min: 30), duration_minutes: 60) }
    let!(:booth_shift) do
      create(:shift, organization: org, house_role: booth, source: seven, starts_at: seven.date_and_time - 30.minutes, ends_at: seven.ends_at)
    end
    # The night's crew, one of them tied to the first show the way a hand-added
    # shift can be: still the night's, not that show's.
    let!(:house_shift) do
      create(:shift, organization: org, house_role: house_staff, source: seven,
                     starts_at: thursday.in_time_zone.change(hour: 18), ends_at: thursday.in_time_zone.change(hour: 18) + 6.5.hours)
    end
    let!(:bar_shift) do
      create(:shift, organization: org, house_role: bartender,
                     starts_at: thursday.in_time_zone.change(hour: 18), ends_at: thursday.in_time_zone.change(hour: 18) + 6.hours)
    end
    let!(:party_before) do
      create(:shift, organization: org, house_role: bartender, required_count: 1,
                     starts_at: thursday.in_time_zone.change(hour: 14), ends_at: thursday.in_time_zone.change(hour: 17))
    end

    before do
      org.people << [ fay, miles, tess ]
      booth_shift.shift_assignments.create!(person: tess)
      house_shift.shift_assignments.create!(person: fay)
      bar_shift.shift_assignments.create!(person: miles)
    end

    it "gives the night's crew its own row by its start, and each show only its own per-show roles" do
      doc = page(week_start: week_start.to_s)
      column = doc.at_css("[data-day-column='#{thursday.iso8601}']")
      rows = column.css("[data-home-show], [data-home-staffing-day]")
      expect(rows.map { |n| n["data-home-show"] || n.at_css("span span:nth-child(2)").text.strip })
        .to eq([ "Bartender", "House Staff, Bartender", seven.id.to_s, thu_show.id.to_s, eight.id.to_s ])
      crew = rows[1]
      expect(crew["href"]).to eq(manage_staffing_scheduling_path(day: thursday.iso8601))
      expect(crew.text).to include("6:00")
      expect(crew.at_css("[data-chip='staffing']").text).to include("2/2")
      expect(crew["title"]).to include("6:00 PM–12:30 AM", "Fay Lily", "Miles Rowe")
      expect(rows[0].at_css("[data-chip='staffing']").text).to include("0/1")

      expect(doc.at_css("[data-home-show='#{seven.id}'] [data-chip='staffing']").text).to include("1/1")
      expect(doc.at_css("[data-home-show='#{eight.id}'] [data-chip='staffing']").text).to include("No shifts")
      seven_modal = doc.at_css("#show-modal-#{seven.id}")
      expect(seven_modal.text).to include("Booth Tech", "Tess Ng")
      expect(seven_modal.text).not_to include("Fay Lily", "Miles Rowe")
    end

    it "names the per-show role a show is missing when Role Call is on" do
      org.update!(alert_uncovered_show_roles: true)
      doc = page(week_start: week_start.to_s)
      chip = doc.at_css("[data-home-show='#{eight.id}'] [data-chip='staffing']")
      expect(chip["data-tone"]).to eq("warn")
      expect(chip.text).to include("Needs Booth Tech")
      expect(doc.at_css("#show-modal-#{eight.id} [data-modal-missing]").text).to include("Needs Booth Tech")
      expect(doc.at_css("[data-home-show='#{seven.id}'] [data-chip='staffing']").text).to include("1/1")

      eight.update!(staffing_coverage_exempt_role_ids: [ booth.id ])
      doc = page(week_start: week_start.to_s)
      expect(doc.at_css("[data-home-show='#{eight.id}'] [data-chip='staffing']").text).not_to include("Needs")
    end

    it "shows the same order on a phone, worded, with who's on" do
      doc = page(day: thursday.iso8601)
      day = doc.at_css("[data-home-day='#{thursday.iso8601}']")
      expect(day.text).to include("3 shows")
      kinds = day.css("[data-home-show], [data-home-staffing-day]").map { |n| n["data-home-show"] ? "show" : "staffing" }
      expect(kinds).to eq(%w[staffing staffing show show show])
      crew = day.css("[data-home-staffing-day]")[1]
      expect(crew.text).to include("House Staff, Bartender", "until 12:30 AM", "Fully staffed", "Fay Lily", "Miles Rowe")
    end

    it "draws no staffing row and no show chip with only per-show shifts, or no per-show roles" do
      [ house_shift, bar_shift, party_before ].each(&:destroy!)
      doc = page(week_start: week_start.to_s)
      expect(doc.at_css("[data-day-column='#{thursday.iso8601}'] [data-home-staffing-day]")).to be_nil

      booth_shift.destroy!
      booth.update!(role_type: :house)
      doc = page(week_start: week_start.to_s)
      expect(doc.at_css("[data-home-show='#{seven.id}'] [data-chip='staffing']")).to be_nil
    end
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
