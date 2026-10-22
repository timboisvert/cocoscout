# frozen_string_literal: true

require "rails_helper"

# The V1.1 desktop panel (navigation canvas): the universal Messages and
# Notifications icons in both modes, no Messages nav item, no dashboard
# switcher, the organization band in production mode, and the mode switch
# at the foot of the account menu.
RSpec.describe "The desktop panel", type: :request do
  let(:user) { create(:user) }
  let!(:person) { Person.create!(email: user.email_address, name: "Tim Boisvert", user: user) }

  def sign_in
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  def panel
    Nokogiri::HTML(response.body).at_css("nav[data-v11-panel]")
  end

  context "for someone with no production access" do
    before { sign_in }

    it "has the two icons, no Messages item, no switcher, and Start producing" do
      user.notifications.create!(category: "pay", kind: "sent", title: "Your pay is on its way")
      get my_dashboard_path
      expect(panel.at_css('[data-universal-icon="messages"]')["href"]).to eq(messages_path)
      bell = panel.at_css('[data-universal-icon="notifications"]')
      expect(bell["href"]).to eq(notifications_path)
      expect(bell["aria-label"]).to eq("Notifications, 1 unread")
      expect(panel.css("a").map(&:text).map(&:squish)).not_to include("My Messages")
      expect(response.body).not_to include("Talent Dashboard", "Production Dashboard")
      expect(panel.text).to include("Start producing")
      expect(panel.at_css("[data-mode-switch]")).to be_nil
    end
  end

  context "for a manager" do
    let(:org) { Organization.create!(name: "Stars & Garters", owner: user) }

    before do
      OrganizationRole.create!(user: user, organization: org, company_role: "manager")
      org.people << person
      sign_in
    end

    it "offers Enter production mode at the foot of the account menu on My" do
      get my_dashboard_path
      switch = panel.at_css('[data-mode-switch="enter"]')
      expect(switch["href"]).to eq(manage_path)
      expect(switch.text).to include("Enter production mode", "Stars & Garters")
      expect(switch["class"]).to include("bg-pink-500")
      expect(switch["class"]).not_to include("pink-700")
    end

    it "shows the organization band and Exit production mode in Manage" do
      get manage_path
      expect(panel.text).to include("Stars & Garters", "Production mode")
      expect(panel.at_css('[data-mode-switch="exit"]')["href"]).to eq(my_dashboard_path)
      expect(panel.at_css('[data-universal-icon="messages"]')["href"]).to eq(messages_path)
      expect(panel.css("a").map(&:text).map(&:squish)).not_to include("Messages")
    end

    it "keeps the panel on Account settings, without a band" do
      get account_notifications_path
      expect(panel).to be_present
      expect(panel.text).not_to include("Production mode")
    end
  end
end

RSpec.describe "The phone's navigation on the website", type: :request do
  let(:user) { create(:user) }
  let!(:person) { Person.create!(email: user.email_address, name: "Tim Boisvert", user: user) }
  let(:org) { Organization.create!(name: "Stars & Garters", owner: user) }

  before do
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    org.people << person
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  def phone_nav
    Nokogiri::HTML(response.body).at_css('[data-controller="mobile-nav"]')
  end

  it "has the icons in the top bar, no switcher, and Enter production mode at the bottom of the menu" do
    get my_dashboard_path
    expect(phone_nav.css("[data-universal-icon]").map { |a| a["data-universal-icon"] }).to eq(%w[messages notifications])
    expect(phone_nav.text).not_to include("Talent Dashboard", "Switch dashboard")
    expect(phone_nav.at_css('[data-mode-switch="enter"]')["class"]).to include("bg-pink-500")
    expect(phone_nav.css("a").map { |a| a.text.squish }).not_to include("My Messages")
  end

  it "names the organization in the top bar in production mode, with its sheet" do
    get manage_path
    expect(phone_nav.text).to include("Stars & Garters", "Production mode", "Exit production mode")
    expect(phone_nav.at_css('[data-mobile-nav-target="orgPopup"]')).to be_present
  end
end

RSpec.describe "The mode-switch notice", type: :request do
  let(:user) { create(:user) }
  let(:org) { Organization.create!(name: "Stars & Garters", owner: user) }

  before do
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  it "says so, with Exit, when a link brings someone from My into production mode, and only then" do
    get my_dashboard_path
    get manage_path
    notice = Nokogiri::HTML(response.body).at_css("[data-mode-switch-notice]")
    expect(notice.text).to include("You're in production mode for", "Stars & Garters")
    expect(notice.at_css("a")["href"]).to eq(my_dashboard_path)

    get manage_path
    expect(response.body).not_to include("data-mode-switch-notice")
  end

  it "never shows on a V1 phone, which has no production mode" do
    get my_dashboard_path
    get manage_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }
    expect(response.body).not_to include("data-mode-switch-notice")
  end
end
