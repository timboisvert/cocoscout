# frozen_string_literal: true

require "rails_helper"

# The V1.1 app menu (NativeAppHelper#native_nav) goes only to generation-2
# builds; V1 installs get exactly the menu they always did.
RSpec.describe "The app's V1.1 menu", type: :request do
  let(:user) { create(:user) }
  let!(:person) { Person.create!(email: user.email_address, name: "Tim Boisvert", user: user) }
  let(:org) { Organization.create!(name: "Stars & Garters", owner: user) }
  let(:v1) { "Mozilla/5.0 (iPhone) AppleWebKit Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu]" }
  let(:v1_1) { "CocoScout/1.1 (12; nav 2) #{v1}" }

  before do
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    org.people << person
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  def bridge
    Nokogiri::HTML(response.body).at_css('[data-controller="bridge--menu"]')
  end

  it "sends V1 installs no nav, and their menu still has My Messages" do
    get my_dashboard_path, headers: { "User-Agent" => v1 }
    expect(bridge["data-bridge--menu-nav-value"]).to be_nil
    expect(JSON.parse(bridge["data-bridge--menu-menu-value"]).map { |i| i["title"] }).to include("My Messages")
  end

  it "sends a V1.1 build My's tiles without Messages, the icons, and Enter production mode" do
    get my_dashboard_path, headers: { "User-Agent" => v1_1 }
    nav = JSON.parse(bridge["data-bridge--menu-nav-value"])
    expect(nav["mode"]).to eq("my")
    titles = nav["sections"].flat_map { |s| s["items"] }.map { |i| i["title"] }
    expect(titles).to include("Home", "Shows & Events")
    expect(titles).not_to include("My Calendar", "My Shows")
    expect(titles).not_to include("My Messages")
    expect(nav.dig("icons", "notifications", "path")).to eq(notifications_path)
    expect(nav.dig("modeSwitch", "label")).to eq("Enter production mode")
    expect(nav["organization"]).to be_nil
  end

  it "sends production mode's tiles and organization inside Manage" do
    get manage_path, headers: { "User-Agent" => v1_1 }
    nav = JSON.parse(bridge["data-bridge--menu-nav-value"])
    expect(nav["mode"]).to eq("production")
    expect(nav.dig("organization", "name")).to eq("Stars & Garters")
    expect(nav["sections"].first["items"].first).to include("title" => "Home", "icon" => "house")
    expect(nav.dig("modeSwitch", "label")).to eq("Exit production mode")
    expect(nav.dig("icons", "messages", "path")).to eq(manage_messages_path)
  end
end

RSpec.describe "The app's production-mode strip", type: :request do
  let(:user) { create(:user) }
  let(:org) { Organization.create!(name: "Stars & Garters", owner: user) }

  before do
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  it "shows only for V1.1 builds in Manage" do
    v1 = "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS"
    get manage_path, headers: { "User-Agent" => "CocoScout/1.1 (12; nav 2) #{v1}" }
    expect(response.body).to include("data-production-strip")
    get my_dashboard_path, headers: { "User-Agent" => "CocoScout/1.1 (12; nav 2) #{v1}" }
    expect(response.body).not_to include("data-production-strip")
  end
end
