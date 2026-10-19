# frozen_string_literal: true

require "rails_helper"

# Tap to Pay in the Android app (2026-10-19): the same pages and bridge
# messages as the iPhone's, but in Android's words. Apple's name, its phone,
# its picture and its disclaimer are the iPhone's alone (Apple's review); on
# Android it's plain "Tap to Pay" on "this phone".
RSpec.describe "Tap to Pay on Android", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, tap_to_pay: true) } }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
  let(:seller) { create(:user, password: password) }
  let(:android) do
    { "User-Agent" => "Mozilla/5.0 (Linux; Android 16; Pixel 8) Hotwire Native Android; Turbo Native Android; " \
                      "bridge-components: [form menu door-scanner push tap-to-pay];" }
  end
  let(:iphone) { { "User-Agent" => "Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu door-scanner push tap-to-pay];" } }

  before do
    org.locations.create!(name: "Playhouse", address1: "48 Lantern St", city: "Providence", state: "RI", postal_code: "02903", default: true)
    org.ticketing_access_grants.create!(user: seller, access_level: "box_office")
    create(:person, user: seller, name: "Robin Seller").tap { |person| seller.update!(default_person: person) }
    allow(Stripe::Terminal::Location).to receive(:create).and_return(Stripe::Terminal::Location.construct_from(id: "tml_1"))
    allow(Stripe::Terminal::ConnectionToken).to receive(:create).and_return(Stripe::Terminal::ConnectionToken.construct_from(secret: "pst_1"))
    post handle_signin_path, params: { email_address: seller.email_address, password: password }, headers: android
  end

  def no_apple(body)
    expect(body).not_to include("iPhone")
    expect(body).not_to include("Apple")
  end

  it "has its own page in plain Tap to Pay words, with none of Apple's picture or disclaimer" do
    get door_tap_to_pay_path, headers: android
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    setup = page.at_css("[data-controller~='tap-to-pay-setup']")
    expect(setup["data-bridge--tap-to-pay-location-id-value"]).to eq("tml_1")
    expect(setup["data-bridge--tap-to-pay-connection-token-url-value"]).to eq(door_tap_to_pay_token_path(organization_id: org.id))
    # Every panel the setup controller shows, so none is missing on Android.
    %w[checking browser notSetUp preparing progress progressText ready needsAdmin failed failedText].each do |target|
      expect(page.at_css("[data-tap-to-pay-setup-target='#{target}']")).to be_present, target
    end
    expect(response.body).to include("Set up Tap to Pay", "Getting Tap to Pay ready", "This phone can take payments with Tap to Pay.",
                                     "click->bridge--tap-to-pay#enable", "click->bridge--tap-to-pay#howToTap", "Try it out at the door")
    expect(response.body).not_to include("tap_to_pay_hero", "Terms apply.", "Stripe")
    no_apple(response.body)
  end

  it "names it Tap to Pay in the menu, with what the app warms up with" do
    get door_tap_to_pay_path, headers: android # makes the organization's Terminal Location
    get my_dashboard_path, headers: android
    bridge = Nokogiri::HTML(response.body).at_css("[data-controller='bridge--menu']")
    menu = JSON.parse(bridge["data-bridge--menu-menu-value"])
    expect(menu.find { |item| item["id"] == "tap_to_pay" }).to include("title" => "Tap to Pay", "path" => door_tap_to_pay_path)
    tap_to_pay = JSON.parse(bridge["data-bridge--menu-tap-to-pay-value"])
    expect(tap_to_pay).to include("settingsPath" => door_tap_to_pay_path, "userKey" => seller.id.to_s, "locationId" => "tml_1")
  end

  it "names the door's button Tap to Pay, for this phone" do
    get door_path(listing), headers: android
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-door-sell-target='tapButton']").text.squish).to eq("Tap to Pay")
    expect(page.at_css("[data-controller~='door-sell']")["data-door-sell-tap-label-value"]).to eq("Tap to Pay")
    expect(response.body).to include("Tap to Pay takes their card or phone right on this phone.")
    expect(response.body).not_to include("iPhone")
  end

  it "asks for the tap on the back of this phone, naming no one's phone or wallet" do
    allow(Stripe::PaymentIntent).to receive(:create)
    post door_sell_path(listing), params: { kind: "tap", quantities: { general.id => 2 } }, headers: android
    order = listing.ticket_orders.order(:id).last
    get door_tap_path(listing, token: order.token), headers: android
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hold their card or phone to the back of this phone", "Contactless card, or a phone or watch wallet",
                                     "Scan for a receipt")
    no_apple(response.body)
  end

  it "leaves the iPhone app's words as Apple asks" do
    post handle_signin_path, params: { email_address: seller.email_address, password: password }, headers: iphone
    get door_path(listing), headers: iphone
    expect(Nokogiri::HTML(response.body).at_css("[data-door-sell-target='tapButton']").text.squish).to eq("Tap to Pay on iPhone")
    get door_tap_to_pay_path, headers: iphone
    expect(response.body).to include("Set up Tap to Pay on iPhone", "Terms apply.")
  end
end
