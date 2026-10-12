# frozen_string_literal: true

require "rails_helper"

# What the iOS app gets from the web app: its tabs and badges (per person,
# from the web nav's rules), the More screen, where signing in and out lands,
# and pages that drop web-only chrome inside the app.
RSpec.describe "The iOS app's web side", type: :request do
  let(:in_app) { { "User-Agent" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form tabs];" } }
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:org) { create(:organization, :pro) }

  def sign_in(as = user)
    post handle_signin_path, params: { email_address: as.email_address, password: password }, headers: in_app
  end

  def tabs = bridge_value("tabs")
  def menu = bridge_value("menu")

  def bridge_value(name)
    json = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--tabs']")&.[]("data-bridge--tabs-#{name}-value")
    json && JSON.parse(json)
  end

  def performs!
    pool = create(:talent_pool, production: create(:production, organization: org))
    TalentPoolMembership.create!(talent_pool: pool, member: person)
  end

  describe "tabs" do
    it "gives a performer Home, Tasks, Messages and More, with badges" do
      performs!
      sign_in
      get my_dashboard_path, headers: in_app

      expect(tabs.map { |tab| tab["id"] }).to eq(%w[home tasks messages more])
      expect(tabs.find { |tab| tab["id"] == "messages" }).to include("path" => my_messages_path, "icon" => "envelope", "badge" => 0)
    end

    it "adds the Door for someone who works a door" do
      TicketingProfile.for(org).update!(enabled: true)
      org.ticketing_access_grants.create!(user: user, access_level: "check_in")
      sign_in
      get my_dashboard_path, headers: in_app

      expect(tabs.map { |tab| tab["id"] }).to eq(%w[home tasks messages door more])
      expect(tabs.find { |tab| tab["id"] == "door" }["path"]).to eq(door_index_path)
    end

    it "sends the full menu too, with the Door for anyone who can work one" do
      TicketingProfile.for(org).update!(enabled: true)
      create(:organization_role, :manager, user: user, organization: org)
      sign_in
      get my_dashboard_path, headers: in_app

      expect(menu.map { |item| item["id"] }).to eq(%w[home messages tasks shows door courses auditions documents payments productions profile settings])
      expect(menu.find { |item| item["id"] == "payments" }).to include("title" => "Payments", "path" => my_payments_path, "icon" => "dollarsign.circle")
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

    it "gives house staff who don't perform Shifts in place of Tasks" do
      create(:organization_staff_member, organization: org, person: person)
      sign_in
      get my_dashboard_path, headers: in_app

      expect(tabs.map { |tab| tab["id"] }).to eq(%w[home shifts messages more])
    end

    it "sends no tabs to a signed-out app, and none to a browser" do
      get signin_path, headers: in_app
      expect(tabs).to eq([])

      sign_in
      get my_dashboard_path
      expect(tabs).to be_nil
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

  it "lists everything that isn't a tab on the More screen" do
    TicketingProfile.for(org).update!(enabled: true)
    org.ticketing_access_grants.create!(user: user, access_level: "check_in")
    sign_in
    get my_account_path, headers: in_app

    page = Nokogiri::HTML(response.body)
    links = page.css("nav[aria-label='More'] a").map { |a| a["href"] }
    expect(links).to include(my_shows_path, my_payments_path, profile_path, account_path)
    expect(links).not_to include(my_dashboard_path, my_messages_path, my_tasks_path, door_index_path)
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
    expect(response.body).to include("bridge--tabs")
  end

  it "serves page rules the app can read" do
    rules = JSON.parse(Rails.public_path.join("hotwire-native/path-configuration.json").read)["rules"]
    open_in = rules.select { |rule| rule["properties"]["open_in"] }.to_h { |rule| [ rule["properties"]["open_in"], rule["patterns"] ] }

    expect(open_in["safari"]).to include("^/manage")
    expect(open_in["document"].any? { |pattern| Regexp.new(pattern).match?("/my/tax-forms/12/w9/copy") }).to be(true)
    expect(rules.flat_map { |rule| rule["patterns"] }.any? { |pattern| Regexp.new(pattern).match?("/my/signups/ABC12/form") }).to be(true)
  end
end
