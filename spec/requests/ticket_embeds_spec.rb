# frozen_string_literal: true

require "rails_helper"

# Selling on the theater's own website: one script turns a tag into a framed
# box office, and the framed pages keep embed mode all the way through
# checkout.
RSpec.describe "Ticketing embed", type: :request do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:show) { create(:show, production: create(:production, organization: org, name: "Improvised Animorphs"), date_and_time: 5.days.from_now) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  it "serves the one script, pointing back at this site" do
    get tickets_embed_script_path
    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to include("data-cocoscout-tickets").and include("/tickets/embed/").and include("http://www.example.com")
    expect(response.headers["Cache-Control"]).to include("public")
  end

  it "lets any site frame the embed pages, and keeps embed mode on every link" do
    get tickets_embed_box_office_path(org: "starsandgarters")
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Frame-Options"]).to be_nil
    expect(response.headers["Content-Security-Policy"]).to eq("frame-ancestors *")
    expect(response.body).to include("cocoscout:height")
    expect(response.body).to include(tickets_event_path(org: "starsandgarters", event: listing.slug, embed: "1"))
  end

  it "keeps the ordinary pages unframeable" do
    get tickets_box_office_path(org: "starsandgarters")
    expect(response.headers["X-Frame-Options"]).to eq("SAMEORIGIN")
  end

  it "carries embed mode through checkout" do
    get tickets_embed_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include('name="embed"')

    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug),
         params: { quantities: { general.id => 1 }, embed: "1" }
    order = TicketOrder.last
    expect(response).to redirect_to(tickets_checkout_path(token: order.token, embed: "1"))

    follow_redirect!
    expect(response.headers["X-Frame-Options"]).to be_nil
    expect(response.body).to include(tickets_checkout_done_url(token: order.token, embed: "1"))
  end

  it "gives managers the code to paste" do
    admin = create(:user, email_address: "boisvert@gmail.com", password: "Password123!")
    create(:organization_role, :manager, user: admin, organization: org)
    post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
    get manage_path

    get manage_ticketing_settings_section_path(section: "embed")
    expect(response.body).to include(%(data-cocoscout-tickets=&quot;starsandgarters&quot;))
    expect(response.body).to include("/tickets/embed.js").and include(listing.slug)
  end
end
