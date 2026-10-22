# frozen_string_literal: true

require "rails_helper"

# The one page-top model (shared/module_header; Tim, 2026-10-21): the title,
# an optional description for desktop, and the actions as cards from sm up or
# icon tiles in a scrolling row on a phone; one or two actions are buttons in
# the title row. Home puts its title first, then what needs attention.
RSpec.describe "The module header", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "draws a page with sections as cards from sm up and icon tiles in a scrolling row on a phone, no Sections fold" do
    get manage_casting_path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    header = doc.at_css("[data-module-header]")
    expect(header.at_css("h1")["class"]).to include("text-xl sm:text-4xl")
    expect(header.text).not_to include("Sections")
    tiles = header.at_css("[data-section-tiles]")
    expect(tiles["data-controller"]).to eq("scroll-row")
    expect(tiles.css("a").map { |a| a.text.squish }).to include("Casting Tables", "Availability", "Talent Pool")
    expect(tiles.css("[data-scroll-row-target='left'], [data-scroll-row-target='right']").size).to eq(2)
    expect(tiles.at_css("[data-scroll-row-target='track']")["class"]).to include("overflow-x-auto", "[scrollbar-width:none]")
    expect(header.at_css("[data-module-buttons]")).to be_nil
  end

  it "keeps the description for desktop only" do
    get manage_staffing_index_path
    expect(response).to have_http_status(:ok)
    header = Nokogiri::HTML(response.body).at_css("[data-module-header]")
    description = header.css("div").find { |d| d.text.include?("Your team") }
    expect(description["class"]).to include("hidden sm:block")
  end

  it "puts one or two actions in the title row as buttons, at every width" do
    get manage_shows_path
    header = Nokogiri::HTML(response.body).at_css("[data-module-header]")
    buttons = header.at_css("[data-module-buttons]")
    expect(buttons.css("a, button").map { |b| b.text.squish }).to eq([ "Calendar", "Schedule Event" ])
    expect(header.at_css("[data-section-tiles]")).to be_nil
  end

  it "drops the title in the app, where the nav bar has it" do
    get manage_casting_path, headers: { "User-Agent" => app_ua }
    header = Nokogiri::HTML(response.body).at_css("[data-module-header]")
    expect(header.at_css("h1")).to be_nil
    expect(header.at_css("[data-section-tiles]")).to be_present
  end

  it "heads My's landing pages the same way, with My Shows & Events" do
    get my_shows_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("[data-module-header] h1").text.squish).to eq("My Shows & Events")
    get my_tasks_path
    expect(Nokogiri::HTML(response.body).at_css("[data-module-header] h1").text.squish).to eq("My Tasks & Availability")
    get my_courses_path
    header = Nokogiri::HTML(response.body).at_css("[data-module-header]")
    expect(header.at_css("h1").text.squish).to eq("My Courses")
    expect(header.at_css("[data-module-buttons]").text.squish).to eq("Find a course")
  end

  it "puts Home first on both Home pages, then what needs attention" do
    get manage_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body.index("data-module-header")).to be < body.index("production_next_steps")
    get my_dashboard_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(Nokogiri::HTML(body).at_css("[data-module-header] h1").text.squish).to eq("Home")
    expect(body.index("data-module-header")).to be < body.index("talent_welcome")
  end

  it "says My Shows & Events on My and Shows & Events in production mode, everywhere" do
    get my_dashboard_path
    expect(response.body).to include("My Shows &amp; Events")
    get manage_path
    expect(response.body).to include(">Shows &amp; Events<")
    # The apps' menus are JSON (native_nav_spec covers their words).
  end
end
