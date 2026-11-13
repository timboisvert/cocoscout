# frozen_string_literal: true

require "rails_helper"

# Counting use of the iPhone and Android apps on our own server
# (docs/mobile_app_analytics.md; Tim, 2026-10-28): a day per person and a
# page counter, only for real page loads in the app, never while
# impersonating; read on superadmin's App usage page.
RSpec.describe "App usage", type: :request do
  let(:password) { "Password123!" }
  let(:iphone_app) { { "User-Agent" => "CocoScout/1.1 (6; nav 2) Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu]" } }
  let(:v1_android_app) { { "User-Agent" => "Mozilla/5.0 (Linux; Android 16; Pixel 8) Hotwire Native Android; Turbo Native Android; bridge-components: [form menu push]" } }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Ida Performer").tap { |p| user.update!(default_person: p) } }

  def sign_in(as = user, headers = {})
    post handle_signin_path, params: { email_address: as.email_address, password: password }, headers: headers
  end

  it "records nothing for the website" do
    sign_in
    get my_dashboard_path
    expect(AppActivityDay.count).to eq(0)
    expect(AppPageDay.count).to eq(0)
  end

  it "records one day per person in the app and counts every page load, with the build" do
    sign_in(user, iphone_app)
    get my_dashboard_path, headers: iphone_app
    get my_dashboard_path, headers: iphone_app
    get my_shows_path, headers: iphone_app

    day = AppActivityDay.sole
    expect(day).to have_attributes(user_id: user.id, day: Date.current, platform: "ios", app_version: "1.1", nav: 2)
    expect(AppPageDay.find_by!(page: "my/dashboard#index", platform: "ios").views).to eq(2)
    expect(AppPageDay.find_by!(page: "my/shows#index").views).to eq(1)
  end

  it "tells Android from iPhone, and a V1 build by its missing version" do
    sign_in(user, v1_android_app)
    get my_dashboard_path, headers: v1_android_app
    expect(AppActivityDay.sole).to have_attributes(platform: "android", app_version: nil, nav: 1)
  end

  it "doesn't count a frame, a prefetch, or a superadmin impersonating" do
    sign_in(user, iphone_app)
    get my_dashboard_path, headers: iphone_app.merge("Turbo-Frame" => "modal")
    get my_dashboard_path, headers: iphone_app.merge("X-Sec-Purpose" => "prefetch")
    expect(AppPageDay.count).to eq(0)

    allow_any_instance_of(ApplicationController).to receive(:impersonating?).and_return(true) # rubocop:disable RSpec/AnyInstance
    get my_dashboard_path, headers: iphone_app
    expect(AppActivityDay.count).to eq(0)
  end

  describe "the superadmin page" do
    let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }

    it "shows people in the app by platform, the builds and the pages, without the App Review accounts" do
      ios_person = create(:user)
      android_person = create(:user)
      reviewer = create(:user, email_address: "app.review@demo.cocoscout.com")
      AppActivityDay.record!(ios_person, platform: "ios", app_version: "1.1", nav: 2)
      AppActivityDay.record!(android_person, platform: "android", app_version: nil, nav: 1, day: 3.days.ago.to_date)
      AppActivityDay.record!(reviewer, platform: "ios", app_version: "1.1", nav: 2)
      2.times { AppPageDay.count!("door#show", platform: "ios") }

      sign_in(superadmin)
      get app_usage_path
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      tiles = doc.css("[data-active-tile]").map { |t| t.text.squish }
      expect(tiles[0]).to include("Today 1", "1 iPhone · 0 Android")
      expect(tiles[2]).to include("Last 30 days 2", "1 iPhone · 1 Android")
      expect(doc.at_css("[data-ever]").text.squish).to include("Ever opened the app 2")

      # Each screen is its own address; the builds and the pages moved to theirs.
      rows = lambda do |section, selector|
        get app_usage_path(section)
        Nokogiri::HTML(response.body).css("#{selector} tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
      end
      expect(rows.call("builds", "[data-versions]")).to eq([ [ "Android", "V1", "1", "100%" ], [ "iPhone", "1.1", "1", "100%" ] ])
      expect(rows.call("screens", "[data-top-pages]")).to eq([ [ "door#show", "", "2" ] ])
      %w[growth people].each do |section|
        get app_usage_path(section)
        expect(response).to have_http_status(:ok)
      end
    end

    # All, iPhone or Android, kept from screen to screen (Tim, 2026-11-13).
    it "filters every screen by platform and keeps the choice in the screens' links" do
      ios_person = create(:user)
      android_person = create(:user)
      AppActivityDay.record!(ios_person, platform: "ios", app_version: "1.2", nav: 2)
      AppActivityDay.record!(android_person, platform: "android", app_version: "1.2", nav: 2)
      AppPageDay.count!("door#show", platform: "ios")
      3.times { AppPageDay.count!("my/shifts#index", platform: "android") }

      sign_in(superadmin)
      get app_usage_path(platform: "android", days: 7)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css("[data-active-tile]").first.text.squish).to include("Today 1", "1 Android")
      expect(doc.css("[data-active-tile]").first.text).not_to include("iPhone")
      expect(doc.css("nav[aria-label='Settings sections'] a").map { |a| a["href"] }).to all(include("platform=android").and(include("days=7")))

      get app_usage_path("screens", platform: "android")
      pages = Nokogiri::HTML(response.body).css("[data-top-pages] tbody tr td:first-child").map { |td| td.text.squish }
      expect(pages).to eq([ "my/shifts#index" ])
    end

    it "counts people new to the app by the week of their first day" do
      travel_to Date.new(2026, 11, 11) do
        early = create(:user)
        late = create(:user)
        AppActivityDay.record!(early, platform: "ios", app_version: "1.1", nav: 2, day: Date.new(2026, 10, 20))
        AppActivityDay.record!(early, platform: "ios", app_version: "1.2", nav: 2, day: Date.new(2026, 11, 10))
        AppActivityDay.record!(late, platform: "android", app_version: "1.2", nav: 2, day: Date.new(2026, 11, 10))

        report = AppUsageReport.new
        expect(report.ever).to include(total: 2, ios: 1, android: 1)
        expect(report.growth.last).to include(week: Date.new(2026, 11, 9), new: { "ios" => 0, "android" => 1 }, total: 2)
        expect(report.new_people(7)).to eq(now: 1, before: 0)
        expect(AppUsageReport.new(platform: "ios").ever[:total]).to eq(1)
      end
    end

    it "is for superadmins only" do
      sign_in
      get app_usage_path
      expect(response).to redirect_to(my_dashboard_path)
    end
  end

  it "keeps weekly cohorts: who came back each week after their first" do
    travel_to Date.new(2026, 10, 28) do
      a = create(:user)
      b = create(:user)
      first_week = Date.current.beginning_of_week - 1.week
      AppActivityDay.record!(a, platform: "ios", app_version: "1.1", nav: 2, day: first_week)
      AppActivityDay.record!(b, platform: "ios", app_version: "1.1", nav: 2, day: first_week + 1)
      AppActivityDay.record!(a, platform: "ios", app_version: "1.1", nav: 2, day: Date.current)

      row = AppUsageReport.new.retention(2).first
      expect(row).to eq(week: first_week, people: 2, returning: [ 1 ])
    end
  end
end
