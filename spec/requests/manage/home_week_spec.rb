# frozen_string_literal: true

require "rails_helper"

# Production Home, show by show (Design B, Tim 2026-10-27): the days across
# the top, a row per show with its ticket, staffing and cast chips, the
# modal behind each, a phone's one day, and three days at a time.
RSpec.describe "Production Home, show by show", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Laugh-Along, Live!") }

  let(:week_start) { Date.current.beginning_of_week + 1.week }
  let(:thursday) { week_start + 3 }
  let(:saturday) { week_start + 5 }
  let!(:thu_show) { create(:show, production: production, date_and_time: thursday.in_time_zone.change(hour: 20), duration_minutes: 90) }
  let!(:sat_show) { create(:show, production: production, date_and_time: saturday.in_time_zone.change(hour: 19), duration_minutes: 90) }
  let!(:role) { create(:role, production: production, name: "Host") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def page(**params)
    get manage_path(**params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "puts a row per show under its day, in time order, each opening its modal" do
    doc = page(week_start: week_start.to_s)
    grid = doc.at_css("[data-home-week]")
    expect(grid.css("[data-day-header]").map { |h| h["data-day-header"] }).to include(thursday.iso8601, saturday.iso8601)
    thu = grid.at_css("[data-day-column='#{thursday.iso8601}']")
    row = thu.at_css("[data-home-show='#{thu_show.id}']")
    expect(row.text).to include("8:00", "Laugh-Along, Live!")
    expect(row["data-modal-id"]).to eq("show-modal-#{thu_show.id}")
    expect(doc.at_css("#show-modal-#{thu_show.id}")).to be_present
    expect(response.body).not_to include("turbo-refresh-method")
  end

  it "narrows a day with nothing on it, and counts the day's shows in its header" do
    doc = page(week_start: week_start.to_s)
    grid = doc.at_css("[data-home-week]")
    expect(grid.at_css("[data-day-column='#{week_start.iso8601}']")).to be_nil
    expect(grid.at_css("[data-day-header='#{thursday.iso8601}']").text).to include("1 show")
  end

  describe "the chips" do
    let(:gus) { create(:person, name: "Gus Lee") }

    it "say where the cast stands: uncast, a vacancy, or all cast" do
      doc = page(week_start: week_start.to_s)
      chip = doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='cast']")
      expect(chip["data-tone"]).to eq("warn")
      expect(chip.text).to include("1 uncast")

      create(:show_person_role_assignment, show: thu_show, assignable: gus, role: role)
      create(:role_vacancy, :with_vacated_by, show: sat_show, role: role)
      doc = page(week_start: week_start.to_s)
      thu_chip = doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='cast']")
      expect(thu_chip["data-tone"]).to eq("warn")
      expect(thu_chip.text).to include("1 to notify")
      sat_chip = doc.at_css("[data-home-show='#{sat_show.id}'] [data-chip='cast']")
      expect(sat_chip["data-tone"]).to eq("bad")
      expect(sat_chip.text).to include("1 open")
      expect(doc.at_css("[data-home-actions] [data-status='vacancies']").text).to include("1 open vacancy")
    end

    it "say where staffing stands once the organization has roles, and nothing on the Producer plan" do
      bartender = create(:house_role, organization: org, name: "Bartender", role_type: :house)
      shift = create(:shift, organization: org, house_role: bartender, source: thu_show, required_count: 2,
                             starts_at: thu_show.date_and_time - 1.hour, ends_at: thu_show.ends_at)
      org.people << gus
      shift.shift_assignments.create!(person: gus)

      doc = page(week_start: week_start.to_s)
      thu_chip = doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='staffing']")
      expect(thu_chip["data-tone"]).to eq("warn")
      expect(thu_chip.text).to include("1/2")
      sat_chip = doc.at_css("[data-home-show='#{sat_show.id}'] [data-chip='staffing']")
      expect(sat_chip.text).to include("No shifts")
      expect(doc.at_css("[data-home-actions] [data-status='staffing']").text).to include("Staffing is a draft")
      modal = doc.at_css("#show-modal-#{thu_show.id}")
      expect(modal.text).to include("Bartender", "Gus Lee", "+ Staff")

      shift.shift_assignments.first.decline!(reason: "Family thing")
      doc = page(week_start: week_start.to_s)
      expect(doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='staffing']")["data-tone"]).to eq("bad")
      expect(doc.at_css("[data-home-actions] [data-status='staffing']").text).to include("1 can't make it")

      org.update!(comped_indefinitely: false)
      doc = page(week_start: week_start.to_s)
      expect(doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='staffing']")).to be_nil
      expect(doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='cast']")).to be_present
    end

    it "say how the tickets are selling, and strike a canceled show through" do
      listing = create(:ticket_listing, organization: org, show: thu_show)
      order = create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: Time.current)
      2.times { create(:ticket, ticket_order: order) }
      create(:ticket_listing, organization: org, show: sat_show, status: "draft")

      doc = page(week_start: week_start.to_s)
      thu_chip = doc.at_css("[data-home-show='#{thu_show.id}'] [data-chip='tickets']")
      expect(thu_chip.text.squish).to eq("2")
      sat_chip = doc.at_css("[data-home-show='#{sat_show.id}'] [data-chip='tickets']")
      expect(sat_chip["data-tone"]).to eq("warn")
      expect(sat_chip.text).to include("Not on sale")
      modal = doc.at_css("#show-modal-#{thu_show.id}")
      expect(modal.text).to include("2 ", "$40")
      expect(modal.at_css("a[href='#{manage_ticket_listing_path(listing)}']")).to be_present

      thu_show.update!(canceled: true)
      doc = page(week_start: week_start.to_s)
      row = doc.at_css("[data-home-show='#{thu_show.id}']")
      expect(row.text).to include("Canceled")
      expect(row.at_css("[data-chip='tickets']").text).to include("2 to refund")
    end
  end

  it "shows the cast as faces with the name on hover in the show's modal" do
    gus = create(:person, name: "Gus Lee")
    create(:show_person_role_assignment, show: thu_show, assignable: gus, role: role)
    modal = page(week_start: week_start.to_s).at_css("#show-modal-#{thu_show.id}")
    face = modal.at_css("[data-faces] [data-controller='tooltip']")
    expect(face["data-tooltip-text"]).to eq("Gus Lee")
    expect(face.text).to include("GL")
    expect(modal.at_css("a[href='#{manage_casting_production_path(production)}']")).to be_present
  end

  it "works one day at a time on a phone, and three days at a time when asked" do
    doc = page(day: saturday.iso8601)
    day = doc.at_css("[data-home-day]")
    expect(day["data-home-day"]).to eq(saturday.iso8601)
    expect(day.at_css("[data-home-show='#{sat_show.id}']")).to be_present
    expect(day.at_css("[data-home-show='#{thu_show.id}']")).to be_nil
    expect(day.at_css("[data-strip-day='#{saturday.iso8601}']")["aria-current"]).to eq("date")
    expect(day["data-day-swipe-next-url-value"]).to eq(manage_path(day: (saturday + 1).iso8601))
    expect(doc.at_css("#home-jump")).to be_present

    doc = page(days: 3, day: thursday.iso8601)
    headers = doc.css("[data-home-week] [data-day-header]").map { |h| h["data-day-header"] }
    expect(headers).to eq([ thursday.iso8601, (thursday + 1).iso8601, saturday.iso8601 ])
    expect(doc.at_css("[data-days-toggle] .bg-pink-500").text).to eq("3 days")

    # The choice sticks until changed.
    doc = page(day: thursday.iso8601)
    expect(doc.css("[data-home-week] [data-day-header]").size).to eq(3)
    doc = page(days: 7, week_start: week_start.to_s)
    expect(doc.at_css("[data-days-toggle] .bg-pink-500").text).to eq("7 days")
    expect(doc.css("[data-home-week] [data-day-header]").size).to eq(2)
  end

  it "opens a week calendar whose rows go to that week, and has no month grid" do
    doc = page(week_start: week_start.to_s)
    picker = doc.at_css("[data-week-picker]")
    row = picker.at_css("a[data-week-row='#{week_start.iso8601}']")
    expect(row["href"]).to eq(manage_path(week_start: week_start.to_s, days: 7))
    expect(row["class"]).to include("bg-pink-500")
    expect(response.body).not_to include("calendar-day")
  end

  # The page costs a fixed number of queries whatever the week holds.
  it "doesn't cost more with more shows" do
    page(week_start: week_start.to_s)
    baseline = count_queries { get manage_path(week_start: week_start.to_s) }
    4.times { |i| create(:show, production: production, date_and_time: saturday.in_time_zone.change(hour: 15 + i), duration_minutes: 60) }
    scaled = count_queries { get manage_path(week_start: week_start.to_s) }
    expect(scaled - baseline).to be <= 2
  end
end
