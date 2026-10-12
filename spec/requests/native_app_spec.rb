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
    it "lists everything in My with short titles, icons and badges, and who's signed in" do
      sign_in
      get my_dashboard_path, headers: in_app

      expect(menu.map { |item| item["id"] }).to eq(%w[home messages tasks shows courses auditions documents payments productions profile settings])
      expect(menu.find { |item| item["id"] == "messages" }).to include("title" => "Messages", "path" => my_messages_path, "icon" => "envelope", "badge" => 0)
      expect(person_card).to include("name" => "Ida Performer", "email" => user.email_address, "initials" => "IP")
    end

    it "adds the Door for anyone who can work one, managers included" do
      TicketingProfile.for(org).update!(enabled: true)
      create(:organization_role, :manager, user: user, organization: org)
      sign_in
      get my_dashboard_path, headers: in_app

      expect(menu.map { |item| item["id"] }).to eq(%w[home messages tasks shows door courses auditions documents payments productions profile settings])
      expect(menu.find { |item| item["id"] == "door" }["path"]).to eq(door_index_path)
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
    it "lands on My even for someone who last used Manage, and signs out to the sign-in screen" do
      create(:organization_role, :manager, user: user, organization: org)
      post handle_signin_path, params: { email_address: user.email_address, password: password }
      get manage_path
      get signout_path

      sign_in
      expect(response).to redirect_to(my_dashboard_path)

      get signout_path, headers: in_app
      expect(response).to redirect_to(signin_path)
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

  it "serves page rules the app can read" do
    rules = JSON.parse(Rails.public_path.join("hotwire-native/path-configuration.json").read)["rules"]
    open_in = rules.select { |rule| rule["properties"]["open_in"] }.to_h { |rule| [ rule["properties"]["open_in"], rule["patterns"] ] }

    expect(open_in["safari"]).to include("^/manage")
    expect(open_in["document"].any? { |pattern| Regexp.new(pattern).match?("/my/tax-forms/12/w9/copy") }).to be(true)
    expect(rules.flat_map { |rule| rule["patterns"] }.any? { |pattern| Regexp.new(pattern).match?("/my/signups/ABC12/form") }).to be(true)
  end
end
