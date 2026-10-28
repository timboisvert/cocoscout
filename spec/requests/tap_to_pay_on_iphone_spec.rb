# frozen_string_literal: true

require "rails_helper"

# Tap to Pay on iPhone, as Apple's publishing review asks for it (guide v1.8,
# 2026-10-19): switched on per organization; a page of its own in the app
# (set up, the guide, Apple's disclaimer); the app told who may sell with it
# and who may accept Apple's terms; a receipt either way; the launch email
# and push to the people who can sell at its door.
RSpec.describe "Tap to Pay on iPhone", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, tap_to_pay: true) } }
  # Tonight's show, its door open: before it opens a tap is presale and
  # needs the buyer's name and email (door_spec).
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: create(:production, organization: org), date_and_time: 2.hours.from_now)) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
  let(:seller) { create(:user, password: password) }
  let(:checker) { create(:user, password: password) }
  let(:in_app) { { "User-Agent" => "Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu door-scanner push tap-to-pay];" } }
  let(:old_app) { { "User-Agent" => "Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu door-scanner push];" } }

  before do
    org.locations.create!(name: "Playhouse", address1: "48 Lantern St", city: "Providence", state: "RI", postal_code: "02903", default: true)
    org.ticketing_access_grants.create!(user: seller, access_level: "box_office")
    org.ticketing_access_grants.create!(user: checker, access_level: "check_in")
    create(:person, user: seller, name: "Robin Seller").tap { |person| seller.update!(default_person: person) }
    allow(Stripe::Terminal::Location).to receive(:create).and_return(Stripe::Terminal::Location.construct_from(id: "tml_1"))
    allow(Stripe::Terminal::ConnectionToken).to receive(:create).and_return(Stripe::Terminal::ConnectionToken.construct_from(secret: "pst_1"))
  end

  def sign_in(user, headers = in_app)
    post handle_signin_path, params: { email_address: user.email_address, password: password }, headers: headers
  end

  def sign_in_to_manage(user)
    get signout_path
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "has its own page for someone who can sell there, with set up, the guide and Apple's disclaimer" do
    sign_in(seller)
    get door_tap_to_pay_path, headers: in_app
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    setup = page.at_css("[data-controller~='tap-to-pay-setup']")
    expect(setup["data-bridge--tap-to-pay-location-id-value"]).to eq("tml_1")
    expect(setup["data-bridge--tap-to-pay-can-accept-terms-value"]).to eq("false")
    expect(setup["data-bridge--tap-to-pay-connection-token-url-value"]).to eq(door_tap_to_pay_token_path(organization_id: org.id))
    expect(response.body).to include("Set up Tap to Pay on iPhone", "click->bridge--tap-to-pay#enable", "click->bridge--tap-to-pay#howToTap",
                                     "Terms apply.", "Tap to Pay on iPhone requires a supported payment app", "Getting Tap to Pay on iPhone ready",
                                     "An administrator needs to turn it on first", "Try it out at the door", door_index_path)
    expect(response.body).not_to include("Stripe")

    get door_tap_to_pay_token_path(organization_id: org.id), headers: in_app
    expect(response.parsed_body).to eq("secret" => "pst_1")
  end

  it "starts setting up on its own when opened from the awareness page's Get started, so Apple's terms come next" do
    sign_in(seller)
    get door_tap_to_pay_path, headers: in_app
    setup = Nokogiri::HTML(response.body).at_css("[data-controller~='tap-to-pay-setup']")
    expect(setup["data-tap-to-pay-setup-start-value"]).to eq("false")
    expect(setup["data-action"]).to include("tap-to-pay-setup:start->bridge--tap-to-pay#enable")

    get door_tap_to_pay_path(setup: 1), headers: in_app
    setup = Nokogiri::HTML(response.body).at_css("[data-controller~='tap-to-pay-setup']")
    expect(setup["data-tap-to-pay-setup-start-value"]).to eq("true")
  end

  it "is for nobody else: someone who only checks people in, or an organization without it switched on" do
    sign_in(checker)
    get door_tap_to_pay_path, headers: in_app
    expect(response).to have_http_status(:not_found)

    profile.update!(tap_to_pay: false)
    sign_in(seller)
    get door_tap_to_pay_path, headers: in_app
    expect(response).to have_http_status(:not_found)
    get door_tap_to_pay_token_path(organization_id: org.id), headers: in_app
    expect(response).to have_http_status(:not_found)
  end

  it "lets only CocoScout's administrators accept Apple's terms, since every organization's taps go through CocoScout's account" do
    admin = create(:user, email_address: "boisvert@gmail.com", password: password)
    create(:organization_role, :manager, user: admin, organization: org)
    sign_in(admin)
    get door_tap_to_pay_path, headers: in_app
    setup = Nokogiri::HTML(response.body).at_css("[data-controller~='tap-to-pay-setup']")
    expect(setup["data-bridge--tap-to-pay-can-accept-terms-value"]).to eq("true")
  end

  it "sits on Ticketing settings → Door once CocoScout offers it, set in a modal there" do
    profile.update!(tap_to_pay: false)
    create(:organization_role, :manager, user: owner, organization: org)
    sign_in_to_manage(owner)
    get manage_ticketing_settings_section_path(section: "door")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Who can work the door")
    expect(response.body).not_to include("data-tap-to-pay-card")
    patch manage_ticketing_door_tap_to_pay_path, params: { ticketing_profile: { tap_to_pay: "1" } }
    expect(profile.reload.tap_to_pay?).to be(false)

    # A superadmin sees it everywhere, and switching it on offers it.
    admin = create(:user, email_address: "boisvert@gmail.com", password: password)
    create(:organization_role, :manager, user: admin, organization: org)
    sign_in_to_manage(admin)
    get manage_ticketing_settings_section_path(section: "door")
    expect(response.body).to include("data-tap-to-pay-card")
    patch manage_ticketing_door_tap_to_pay_path, params: { ticketing_profile: { tap_to_pay: "1" } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "door"))
    expect(flash[:notice]).to include("Tap to Pay on iPhone is on")
    expect(profile.reload).to have_attributes(tap_to_pay: true, tap_to_pay_offered: true)

    sign_in_to_manage(owner)
    get manage_ticketing_settings_section_path(section: "door")
    card = Nokogiri::HTML(response.body).at_css("[data-tap-to-pay-card]")
    expect(card.text).to include("Tap to Pay on iPhone", "On", "Anyone who can check people in and sell tickets")
    modal = Nokogiri::HTML(response.body).at_css("#tap-to-pay-settings")
    expect(modal.text).to include("Take cards on iPhones at your door", "Setting up an iPhone", "iPhone XS or later", "Terms apply.")
    expect(modal.at_css("input[type=checkbox][name='ticketing_profile[tap_to_pay]']")["checked"]).to eq("checked")
    expect(response.body).not_to include("Stripe")

    # Switched off, it stays on the tab to switch on again.
    patch manage_ticketing_door_tap_to_pay_path, params: { ticketing_profile: { tap_to_pay: "0" } }
    expect(profile.reload.tap_to_pay?).to be(false)
    get manage_ticketing_settings_section_path(section: "door")
    expect(Nokogiri::HTML(response.body).at_css("[data-tap-to-pay-card]").text).to include("Off")
  end

  it "tells the app who can sell with it, only in a copy of the app that has it, and never adds a menu tile" do
    sign_in(seller)
    get my_dashboard_path, headers: in_app
    bridge = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--menu']")
    menu = JSON.parse(bridge["data-bridge--menu-menu-value"])
    # The menu is the My pages only (Tim, 2026-10-19); its setup lives on Settings.
    expect(menu.map { |item| item["id"] }).not_to include("tap_to_pay")
    get account_path, headers: in_app
    settings = Nokogiri::HTML(response.body).at_css("nav[aria-label='Account']")
    expect(settings.text).to include("Tap to Pay on iPhone", "Set it up on this iPhone, and how to take a tap")
    expect(settings.at_css("a[href='#{door_tap_to_pay_path}']")).to be_present
    tap_to_pay = JSON.parse(bridge["data-bridge--menu-tap-to-pay-value"])
    expect(tap_to_pay).to include("settingsPath" => door_tap_to_pay_path, "userKey" => seller.id.to_s, "canAcceptTerms" => false)

    get my_dashboard_path, headers: old_app
    bridge = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--menu']")
    expect(JSON.parse(bridge["data-bridge--menu-menu-value"]).map { |item| item["id"] }).not_to include("tap_to_pay")
    expect(bridge["data-bridge--menu-tap-to-pay-value"]).to be_nil
    get account_path, headers: old_app
    expect(response.body).not_to include("Tap to Pay on iPhone")

    sign_in(checker)
    get my_dashboard_path, headers: in_app
    bridge = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--menu']")
    expect(bridge["data-bridge--menu-tap-to-pay-value"]).to be_nil
  end

  it "names the door's button Tap to Pay on iPhone, first, and never greys it out" do
    sign_in(seller)
    get door_path(listing), headers: in_app
    button = Nokogiri::HTML(response.body).at_css("[data-door-sell-target='tapButton']")
    expect(button.text.squish).to eq("Tap to Pay on iPhone")
    expect(button["class"]).not_to include("disabled:opacity")

    profile.update!(tap_to_pay: false)
    get door_path(listing), headers: in_app
    expect(response.body).not_to include("Tap to Pay on iPhone")
  end

  it "shows a receipt to scan after the tap, approved or not, naming no card and no buyer" do
    sign_in(seller)
    allow(Stripe::PaymentIntent).to receive(:create)
    post door_sell_path(listing), params: { kind: "tap", quantities: { general.id => 2 }, buyer_name: "Dana Scully" }, headers: in_app
    order = listing.ticket_orders.order(:id).last
    get door_tap_path(listing, token: order.token), headers: in_app
    expect(response.body).to include("Scan for a receipt", "The buyer can scan for a receipt.", 'data-door-tap-target="declinedReceipt"')
    expect(response.body).not_to include("M8.288 15.038") # no drawn tap icon of our own

    get tickets_order_receipt_path(token: order.token)
    expect(response.body).to include("Receipt", "Stars &amp; Garters", "2 × General", "Not approved", "No payment was taken", order.code)
    expect(response.body).not_to include("Dana Scully")

    TicketOrderSettlement.settle!(order)
    get tickets_order_receipt_path(token: order.token)
    expect(response.body).to include("Approved", "Paid ")
  end

  it "sends the launch email and notification, with Apple's words, to the people who can sell at its door" do
    create(:organization_role, :manager, user: owner, organization: org)
    expect(TapToPayLaunch.announce!(organizations: [ org ], sender: owner, dry_run: true)).to contain_exactly(owner, seller)

    perform_enqueued_jobs { TapToPayLaunch.announce!(organizations: [ org ], sender: owner) }
    email = ActionMailer::Base.deliveries.find { |mail| mail.to == [ seller.email_address ] }
    expect(email.subject).to eq("Tap to Pay on iPhone")
    expect(email.html_part&.body&.to_s || email.body.to_s).to include("Tap to Pay on iPhone is now available with CocoScout", "Get started", door_tap_to_pay_url(host: "example.com").split("//").last.split("/", 2).last)
    # In the app it's a Notification (V1.1 plan §9), which pushes Apple's words.
    notification = seller.notifications.find_by(kind: "tap_to_pay_launch_message")
    expect(notification).to be_present
    expect(notification.category).to eq("ticketing_milestones")
    expect(notification.title).to start_with("Accept in-person, contactless payments right on your iPhone")
    expect(notification.body).to include("Get started", door_tap_to_pay_url(host: "example.com"))
    expect(Message.where(template_key: "tap_to_pay_launch_message")).to be_empty
  end
end
