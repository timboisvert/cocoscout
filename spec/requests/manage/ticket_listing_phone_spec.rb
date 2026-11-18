# frozen_string_literal: true

require "rails_helper"

# The ticketing show page on a phone (V1.1 plan §4): status, a ⋯ menu with the
# show's actions, and the Door pinned to the bottom.
RSpec.describe "A ticketed show on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner, stripe_account_id: "acct_x", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    TicketingProfile.for(org).update!(enabled: true, slug: "phone-#{org.id}")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "pins the Door and a ⋯ menu of the other actions to the bottom" do
    get manage_ticket_listing_path(listing)
    expect(response).to have_http_status(:ok)
    bar = Nokogiri::HTML(response.body).at_css("[data-ticketing-phone-bar]")
    expect(bar["class"]).to include("sm:hidden", "fixed", "bottom-0")
    expect(bar.css("a").map { |a| a["href"] }).to include(door_path(listing))
    menu = Nokogiri::HTML(response.body).at_css("#ticket-listing-#{listing.id}-actions-sheet")
    expect(menu.text).to include("Orders", "Settings", "Visibility")
    expect(menu.text).not_to include("Scan tickets")
  end

  # The tiles above already count what's sold (Tim, 2026-11-06).
  it "says only the show's status in the bar, never a second count of what's sold" do
    get manage_ticket_listing_path(listing)
    bar = Nokogiri::HTML(response.body).at_css("[data-ticketing-phone-bar]")
    expect(bar.at_css("span span").text.squish).to be_present
    expect(bar.text).not_to match(/\d+ sold/)
  end

  # The Coco button gets itself out of the way (bridge/menu_button_controller.js):
  # the bar runs edge to edge, and only installs that can't move the button
  # still get its width left free.
  it "runs the bar edge to edge in an app build that moves its Coco button, and leaves room in one that can't" do
    old_build = "CocoScout/1.1.2 (15; nav 2) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu door-scanner push]"
    new_build = "CocoScout/1.1.3 (16; nav 2) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu menu-button door-scanner push]"
    bar = ->(agent) do
      get manage_ticket_listing_path(listing), headers: { "User-Agent" => agent }
      Nokogiri::HTML(response.body)
    end

    old_page = bar.call(old_build)
    expect(old_page.at_css("[data-ticketing-phone-bar]")["class"]).to include("pr-[96px]")
    new_page = bar.call(new_build)
    expect(new_page.at_css("[data-ticketing-phone-bar]")["class"]).to include("px-4")
    expect(new_page.at_css("[data-ticketing-phone-bar]")["class"]).not_to include("pr-[96px]")
    # Both are given the piece that says where the button belongs; only the
    # new build's bridge loads it.
    expect(new_page.at_css("[data-controller='bridge--menu-button']")).to be_present
  end

  # From 1.1.4 Coco is in the app's top bar (Tim, 2026-11-09). That build has
  # no menu-button component, like the oldest installs, but nothing floats
  # over its pages: its bar runs edge to edge as the website's does.
  it "runs the bar edge to edge in an app build with Coco in its top bar" do
    get manage_ticket_listing_path(listing), headers: {
      "User-Agent" => "CocoScout/1.1.4 (17; nav 2) CocoMenu/bar Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu door-scanner push]"
    }
    page = Nokogiri::HTML(response.body)
    # A rounded bar, in from the screen's corners and up off its bottom edge (NativeAppHelper#phone_bar_room).
    expect(page.at_css("[data-ticketing-phone-bar]")["class"]).to include("left-3!", "right-3!", "bottom-3!", "rounded-2xl")
    expect(page.at_css("[data-ticketing-phone-bar]")["class"]).not_to include("pr-[96px]")
    expect(page.at_css("main")["class"]).to include("pb-8")
    expect(page.at_css("[data-controller='bridge--menu-button']")).to be_nil
  end
end
