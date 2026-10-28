# frozen_string_literal: true

require "rails_helper"

# What the iOS app gets from the web app: its menu and badges (per person,
# from the web nav's rules) and who's signed in, where signing in and out
# lands, and pages that drop web-only chrome inside the app.
RSpec.describe "The iOS app's web side", type: :request do
  let(:in_app) { { "User-Agent" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu];" } }
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Ida Performer").tap { |p| user.update!(default_person: p) } }
  let(:org) { create(:organization, :pro) }

  def sign_in(as = user)
    post handle_signin_path, params: { email_address: as.email_address, password: password }, headers: in_app
  end

  def menu = bridge_value("menu")
  def person_card = bridge_value("person")

  def bridge_value(name)
    json = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--menu']")&.[]("data-bridge--menu-#{name}-value")
    json.presence && JSON.parse(json)
  end

  describe "the menu" do
    it "lists everything in My, each titled like its page, with icons and badges, and who's signed in" do
      sign_in
      get my_dashboard_path, headers: in_app

      expect(menu.map { |item| item["id"] }).to eq(%w[home messages tasks shows payments documents courses auditions productions profile settings])
      expect(menu.find { |item| item["id"] == "messages" }).to include("title" => "My Messages", "path" => my_messages_path, "icon" => "envelope", "badge" => 0)
      expect(person_card).to include("name" => "Ida Performer", "email" => user.email_address, "initials" => "IP")
    end

    # The Door is the menu's last, full-width bar, and only while a show
    # someone can work is on (DoorTonight; Tim, 2026-10-13).
    it "offers the Door last, only while a show is on, managers included" do
      TicketingProfile.for(org).update!(enabled: true)
      create(:organization_role, :manager, user: user, organization: org)
      production = create(:production, organization: org)
      show = create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 16, 21))
      listing = create(:ticket_listing, organization: org, show: show, status: "on_sale")
      sign_in

      travel_to Time.zone.local(2026, 10, 15, 20) do
        get my_dashboard_path, headers: in_app
        expect(menu.map { |item| item["id"] }).to eq(%w[home messages tasks shows payments documents courses auditions productions profile settings])
      end

      travel_to Time.zone.local(2026, 10, 16, 12) do
        get my_dashboard_path, headers: in_app
        door = menu.last
        expect(door).to include("id" => "door", "title" => "Work the door", "path" => door_index_path)
        expect(door["subtitle"]).to eq("#{listing.display_title} · Starts 9:00 PM")
      end

      # No end time set: still on at 1:30 AM, gone after 2.
      travel_to Time.zone.local(2026, 10, 17, 1, 30) do
        get my_dashboard_path, headers: in_app
        expect(menu.last["subtitle"]).to include("Started 9:00 PM")
      end
      travel_to Time.zone.local(2026, 10, 17, 2, 15) do
        get my_dashboard_path, headers: in_app
        expect(menu.map { |item| item["id"] }).not_to include("door")
      end
    end

    # Ticketing settings → Door: an organization chooses when the app shows it.
    it "follows the organization's Door setting: some hours before, or all the time" do
      profile = TicketingProfile.for(org)
      profile.update!(enabled: true, door_hours_before: 2)
      create(:organization_role, :manager, user: user, organization: org)
      production = create(:production, organization: org)
      show = create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 16, 21))
      listing = create(:ticket_listing, organization: org, show: show, status: "on_sale")
      sign_in

      travel_to Time.zone.local(2026, 10, 16, 12) do
        get my_dashboard_path, headers: in_app
        expect(menu.map { |item| item["id"] }).not_to include("door")
      end
      travel_to Time.zone.local(2026, 10, 16, 19, 30) do
        get my_dashboard_path, headers: in_app
        expect(menu.last).to include("id" => "door", "path" => door_index_path)
      end

      profile.update!(door_in_app: "always")
      travel_to Time.zone.local(2026, 10, 14, 12) do
        get my_dashboard_path, headers: in_app
        expect(menu.last).to include("id" => "door", "title" => "Work the door", "path" => door_index_path,
                                     "subtitle" => "Next: #{listing.display_title} · Fri, Oct 16")
      end
      travel_to Time.zone.local(2026, 10, 18, 12) do
        get my_dashboard_path, headers: in_app
        expect(menu.last).to include("id" => "door", "subtitle" => "No shows coming up")
      end
    end

    it "offers Groups only to someone in one" do
      sign_in
      get my_account_path, headers: in_app
      expect(menu.map { |item| item["id"] }).not_to include("groups")
      expect(response.body).not_to include(">My Groups<")

      GroupMembership.create!(group: create(:group), person: person)
      get my_account_path, headers: in_app
      expect(menu.map { |item| item["id"] }).to include("groups")
      expect(response.body).to include("My Groups")
    end

    it "sends an empty menu and nobody to a signed-out app, and nothing to a browser" do
      get signin_path, headers: in_app
      expect(menu).to eq([])
      expect(person_card).to be_nil

      sign_in
      get my_dashboard_path
      expect(menu).to be_nil
    end

    # The password page is open to everyone, so it doesn't load the session
    # on its own; it must still tell the app you're signed in, or the app
    # resets to its sign-in screen (Reset password "did nothing").
    it "keeps a signed-in person's menu on pages open to everyone" do
      sign_in
      get password_path, headers: in_app
      expect(menu.map { |item| item["id"] }).to include("home", "settings")
    end
  end

  describe "signing in and out in the app" do
    it "lands on My even for someone who last used Manage, and signs out to the welcome screen" do
      create(:organization_role, :manager, user: user, organization: org)
      post handle_signin_path, params: { email_address: user.email_address, password: password }
      get manage_path
      get signout_path

      sign_in
      expect(response).to redirect_to(my_dashboard_path)

      get signout_path, headers: in_app
      expect(response).to redirect_to(welcome_path)
    end

    # Opening the app signed out: a welcome screen first, not the form (Tim, 2026-10-15).
    it "opens on the welcome screen when signed out, with Back links from sign-in and sign-up" do
      get my_dashboard_path, headers: in_app
      expect(response).to redirect_to(welcome_path)

      get welcome_path, headers: in_app
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your shows, your messages, your ticketing. All in one place.", "Create an account",
                                       signin_path, signup_path)

      get signin_path, headers: in_app
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{welcome_path}']")&.text).to include("Back")
      get signup_path, headers: in_app
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{welcome_path}']")&.text).to include("Back")

      # The page rules open it as the app's whole screen; sign-in goes on top of it.
      rules = JSON.parse(Rails.public_path.join("hotwire-native/path-configuration.json").read)["rules"]
      replace_root = rules.select { |rule| rule["properties"]["presentation"] == "replace_root" }.flat_map { |rule| rule["patterns"] }
      expect(replace_root).to include("/welcome$")
      expect(replace_root).not_to include("/signin$")

      sign_in
      get welcome_path, headers: in_app
      expect(response).to redirect_to(my_dashboard_path)
    end

    it "keeps the website's own sign-in" do
      get welcome_path
      expect(response).to redirect_to(signin_path)
      get my_dashboard_path
      expect(response).to redirect_to(signin_path)
      get signin_path
      expect(Nokogiri::HTML(response.body).at_css("a[href='#{welcome_path}']")).to be_nil
    end

    it "still signs a browser out to the home page" do
      sign_in
      get signout_path
      expect(response).to redirect_to(root_path)
    end
  end

  it "gives Account settings rows for the pages its web sidebar would link, in the app only" do
    sign_in
    get account_path, headers: in_app
    links = Nokogiri::HTML(response.body).css("nav[aria-label='Account'] a").map { |a| a["href"] }
    expect(links).to eq([ account_notifications_path, account_profiles_path, account_organizations_path ])

    get account_path
    expect(response.body).not_to include('aria-label="Account"')
  end

  it "lists everything but Home on /my/account" do
    sign_in
    get my_account_path, headers: in_app

    links = Nokogiri::HTML(response.body).css("nav[aria-label='More'] a").map { |a| a["href"] }
    expect(links).to include(my_messages_path, my_shows_path, my_payments_path, profile_path, account_path)
    expect(links).not_to include(my_dashboard_path)
  end

  it "doesn't pitch producing inside the app" do
    sign_in
    get my_dashboard_path, headers: in_app
    expect(response.body).not_to include("Producing your own shows?")

    get my_dashboard_path
    expect(response.body).to include("Producing your own shows?")
  end

  it "drops the profile pages' web menu inside the app" do
    sign_in
    get profile_path
    expect(response.body).to include("#basic-info")

    get profile_path, headers: in_app
    expect(response.body).not_to include("href=\"#basic-info\"")
    expect(response.body).to include("bridge--menu")
  end

  it "keeps a signed-in phone's push notifications in step, in the app only" do
    get signin_path, headers: in_app
    expect(response.body).not_to include("bridge--push")

    sign_in
    get my_dashboard_path, headers: in_app
    push = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--push']")
    expect(push["data-bridge--push-url-value"]).to eq(my_push_token_path)
    expect(push["data-action"]).to include("push:request@window->bridge--push#request")
    expect(response.body).to include("Turn on notifications")

    get my_dashboard_path
    expect(response.body).not_to include("bridge--push", "Turn on notifications")
  end

  it "sends someone to their own phone's Settings to turn notifications off" do
    sign_in
    get account_notifications_path, headers: in_app
    expect(response.body).to include("Open iPhone Settings", "Turned off in iPhone Settings")

    android = { "User-Agent" => "Mozilla/5.0 (Linux; Android 16; Pixel 8) Hotwire Native Android; Turbo Native Android; bridge-components: [form menu push]" }
    get account_notifications_path, headers: android
    expect(response.body).to include("Open Settings", "Turned off in your phone&#39;s Settings")
    expect(response.body).not_to include("iPhone")
  end

  it "hands the door's camera to the app, which titles the page Door" do
    TicketingProfile.for(org).update!(enabled: true)
    # Tonight's, its door open: before it opens there's nothing to scan.
    listing = create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.hours.from_now))
    org.ticketing_access_grants.create!(user: user, access_level: "check_in")
    sign_in

    get door_path(listing), headers: in_app
    page = Nokogiri::HTML(response.body)
    door = page.at_css("[data-controller~='door']")
    expect(door["data-controller"].split).to include("bridge--door-scanner")
    expect(door["data-door-in-app-value"]).to eq("true")
    expect(door["data-bridge--door-scanner-title-value"]).to eq(listing.display_title)
    expect(door["data-action"]).to include("door:scan->bridge--door-scanner#open", "door-scanner:code->door#nativeCode")
    expect(page.at_css("title").text).to eq("Work the door")

    # A browser keeps its own camera, and a title naming the show.
    get door_path(listing)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-controller~='door']")["data-door-in-app-value"]).to eq("false")
    expect(page.at_css("title").text).to eq("Work the door · #{listing.display_title}")
  end

  # iPhone zooms in on small text boxes, and in the app the zoom stuck to
  # every page after (Tim, 2026-10-12). Browsers keep pinch-zoom.
  it "never lets an app page zoom" do
    sign_in
    get my_dashboard_path, headers: in_app
    expect(response.body).to include('content="width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=1"')

    get my_dashboard_path
    expect(response.body).to include("maximum-scale=5")
  end

  it "tells iPhones which links open in the app, signed out and without a redirect" do
    get "/.well-known/apple-app-site-association"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")

    json = JSON.parse(response.body)
    details = json.dig("applinks", "details").sole
    expect(details["appIDs"]).to eq([ "3Y9EQJP24Y.com.cocoscout.app" ])
    expect(details["components"].map { |c| c["/"] }).to include("/my/*", "/door/*", "/claim/*", "/vacancy/*")
    expect(details["components"].map { |c| c["/"] }).not_to include("/manage/*")
    expect(json.dig("webcredentials", "apps")).to eq([ "3Y9EQJP24Y.com.cocoscout.app" ])
  end

  it "tells Android phones the app may open cocoscout.com links, signed out and without a redirect" do
    get "/.well-known/assetlinks.json"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")

    statement = JSON.parse(response.body).sole
    expect(statement["relation"]).to include("delegate_permission/common.handle_all_urls")
    expect(statement["target"]).to include("namespace" => "android_app", "package_name" => "com.cocoscout.app")
    # Google Play's app signing key first: it signs every copy people install.
    expect(statement.dig("target", "sha256_cert_fingerprints").first).to start_with("58:B5:1D:2E")
  end

  it "serves page rules the app can read" do
    rules = JSON.parse(Rails.public_path.join("hotwire-native/path-configuration.json").read)["rules"]
    open_in = rules.select { |rule| rule["properties"]["open_in"] }.to_h { |rule| [ rule["properties"]["open_in"], rule["patterns"] ] }

    expect(open_in["safari"]).to include("^/manage")
    expect(open_in["document"].any? { |pattern| Regexp.new(pattern).match?("/my/tax-forms/12/w9/copy") }).to be(true)
    expect(rules.flat_map { |rule| rule["patterns"] }.any? { |pattern| Regexp.new(pattern).match?("/my/signups/ABC12/form") }).to be(true)

    # Uploaded files (a signed contract) open in the document viewer, not as an error page.
    expect(open_in["document"].any? { |pattern| Regexp.new(pattern).match?("/rails/active_storage/blobs/redirect/abc/contract.pdf") }).to be(true)
    # The marketing site opens in Safari; My pages don't.
    expect(%w[/ /pricing /for-producers].all? { |path| open_in["safari"].any? { |pattern| Regexp.new(pattern).match?(path) } }).to be(true)
    expect(open_in["safari"].any? { |pattern| Regexp.new(pattern).match?("/my/shows") }).to be(false)
    # Form sheets can't be swiped away with what someone typed in them.
    sheets = rules.select { |rule| rule["properties"]["context"] == "modal" }
    expect(sheets).to all(satisfy { |rule| rule["properties"]["modal_dismiss_gesture_enabled"] == false })
  end

  it "keeps the marketing site out of the app" do
    get root_path, headers: in_app
    expect(response).to redirect_to(welcome_path)
    get pricing_path, headers: in_app
    expect(response).to redirect_to(welcome_path)

    sign_in
    get root_path, headers: in_app
    expect(response).to redirect_to(my_dashboard_path)

    get root_path
    expect(response).to have_http_status(:ok)
  end
end
