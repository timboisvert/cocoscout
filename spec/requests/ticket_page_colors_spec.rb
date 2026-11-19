# frozen_string_literal: true

require "rails_helper"

# The pages' colors (Tim, 2026-11-18): the box office's Pages tab sets them
# for the landing page and every ticket page; a production's and a date's
# Ticket page tab can override them with the one override switch.
RSpec.describe "Ticket page colors", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Rising Stars") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let(:colors) { { background: "#0f172a", button: "#fde047", heading: "#ffffff", text: "#cbd5e1" } }

  before do
    listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def body_tag
    Nokogiri::HTML(response.body).at("body")
  end

  it "calls the tab Pages, and its colors reach the landing page and the ticket page" do
    get manage_ticketing_settings_section_path(section: "page")
    doc = Nokogiri::HTML(response.body)
    expect(doc.text).to include("Pages", "Landing page", "Colors")
    expect(doc.css("[data-page-colors-fields] input[type=color]").map { |n| n["name"] })
      .to eq(%w[page_colors[background] page_colors[button] page_colors[heading] page_colors[text]])
    # One reset for the palette, hidden while the colors are the standard ones.
    expect(doc.text).not_to include("Standard")
    expect(doc.at("[data-page-colors-target=reset]")["class"]).to include("hidden")
    expect(doc.at("[data-page-colors-target=reset]").text.squish).to eq("Reset to CocoScout's colors")

    # The standard look: nothing on the page changes.
    get tickets_box_office_path(org: "starsandgarters")
    expect(body_tag["data-page-colors"]).to be_nil

    patch manage_ticketing_settings_page_colors_path, params: { page_colors: colors }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "page"))
    expect(profile.reload.page_colors_hash).to eq(colors)

    get tickets_box_office_path(org: "starsandgarters")
    expect(body_tag.key?("data-page-colors")).to be(true)
    expect(body_tag["style"]).to include("--page-bg: #0f172a", "--page-button: #fde047", "--page-button-ink: #111827")
    expect(response.body).to include("page-heading")

    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(body_tag["style"]).to include("--page-bg: #0f172a")

    # Checkout and the order page wear them too.
    general = listing.ticket_tiers.first
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 2 } }
    order = TicketOrder.order(:id).last
    get tickets_checkout_path(token: order.token)
    expect(body_tag["style"]).to include("--page-bg: #0f172a")
    get tickets_order_path(token: order.token)
    expect(body_tag["style"]).to include("--page-bg: #0f172a")

    # Back to the standard colors: nothing kept.
    patch manage_ticketing_settings_page_colors_path, params: { page_colors: PageColors::DEFAULTS }
    expect(profile.reload.page_colors_hash).to be_empty

    patch manage_ticketing_settings_page_colors_path, params: { page_colors: { background: "blue" } }
    expect(flash[:alert]).to include("must be a color")
  end

  it "lets a production override the box office's colors, and follow them again" do
    profile.update!(page_background_color: "#0f172a")
    get manage_edit_production_ticketing_path(production, section: "sales")
    doc = Nokogiri::HTML(response.body)
    line = doc.at("[data-own-switch=production_ticketing_own_colors] [data-override-line]")
    expect(line.text.squish).to eq("Override your box office's page colors for Rising Stars")
    # Its reset puts back the box office's colors.
    expect(doc.at("[data-settings-card=colors] [data-page-colors-target=reset]").text.squish).to eq("Reset to your box office's colors")
    expect(doc.at("#production_ticketing_page_colors_background")["data-reset"]).to eq("#0f172a")
    expect(doc.at("[data-settings-card=colors] fieldset")["disabled"]).not_to be_nil

    patch manage_update_production_ticketing_path(production, section: "sales"),
          params: { production_ticketing: { own_colors: "1", page_colors: { background: "#fdf2f8", button: "#be185d", heading: "#500724", text: "#831843" } } }
    setup = production.reload.production_ticketing
    expect(setup.page_colors_hash).to include(background: "#fdf2f8", button: "#be185d")

    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(body_tag["style"]).to include("--page-bg: #fdf2f8")

    patch manage_update_production_ticketing_path(production, section: "sales"), params: { production_ticketing: { own_colors: "0" } }
    expect(setup.reload.own_page_colors?).to be(false)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(body_tag["style"]).to include("--page-bg: #0f172a")
  end

  it "lets a date override what it follows, naming its production when the production has its own" do
    ProductionTicketing.for(production).update!(page_background_color: "#fdf2f8", page_button_color: "#be185d", page_heading_color: "#500724", page_text_color: "#831843")
    get manage_edit_ticket_listing_path(listing, section: "page")
    doc = Nokogiri::HTML(response.body)
    line = doc.at("[data-own-switch=ticket_listing_own_colors] [data-override-line]")
    expect(line.text.squish).to eq("Override Rising Stars' page colors for this date")
    # Its reset puts back the production's colors, which it follows.
    expect(doc.at("[data-settings-card=colors] [data-page-colors-target=reset]").text.squish).to eq("Reset to Rising Stars' colors")
    expect(doc.at("#ticket_listing_page_colors_background")["data-reset"]).to eq("#fdf2f8")

    patch manage_ticket_listing_path(listing), params: { section: "page", ticket_listing: { own_colors: "1", page_colors: colors } }
    expect(listing.reload.page_colors_hash).to eq(colors)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(body_tag["style"]).to include("--page-bg: #0f172a")

    patch manage_ticket_listing_path(listing), params: { section: "page", ticket_listing: { own_colors: "0" } }
    expect(listing.reload.own_page_colors?).to be(false)
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(body_tag["style"]).to include("--page-bg: #fdf2f8")
  end
end
