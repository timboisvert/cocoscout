# frozen_string_literal: true

require "rails_helper"

# cocoscout.com/t/CODE: a production's one short code, kept forever; a date is
# a suffix. The code counts visits and remembers itself for the order.
RSpec.describe "Short links", type: :request do
  let(:admin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: admin) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 17, 19, 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let(:link) { production.reload.short_link }

  it "gives a production one code when its ticketing is set up, and the box office one" do
    expect(link).to be_present
    expect(link.code).to match(/\A[A-Z0-9]{5}\z/)
    expect(link.organization).to eq(org)
    expect(ShortLink.canonical_for!(production)).to eq(link)
    expect(profile.reload.short_link).to be_present
  end

  it "sends the code to the production's ticket page, typed in either case, and counts the visit" do
    get "/t/#{link.code.downcase}"
    expect(response).to redirect_to("/tickets/starsandgarters/#{production.public_key}")
    expect(response.cookies["cs_via"]).to eq(link.code)
    expect(link.reload.clicks_count).to eq(1)
    expect(link.last_clicked_at).to be_present
  end

  it "takes a date as a suffix, three ways" do
    [ "oct-17", "2026-10-17", listing.slug ].each do |suffix|
      get "/t/#{link.code}/#{suffix}"
      expect(response).to redirect_to("/tickets/starsandgarters/#{production.public_key}?date=#{suffix}")
      follow_redirect!
      expect(response.body).to include(%(data-ticket-picker-listing-id-value="#{listing.id}")).or include(listing.slug)
    end
  end

  it "keeps working when the production's public key changes" do
    production.update_column(:public_key, "animorphs-2027")
    get "/t/#{link.code}"
    expect(response).to redirect_to("/tickets/starsandgarters/animorphs-2027")
  end

  it "doesn't count bots or HEAD requests" do
    head "/t/#{link.code}"
    get "/t/#{link.code}", headers: { "User-Agent" => "facebookexternalhit/1.1" }
    expect(link.reload.clicks_count).to eq(0)
  end

  it "says so when a code is unknown or archived" do
    get "/t/ZZZZ9"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("This link isn't active any more")

    link.update!(archived_at: Time.current)
    get "/t/#{link.code}"
    expect(response).to have_http_status(:not_found)
  end

  it "sends the box office code to the box office" do
    get "/t/#{profile.reload.short_link.code}"
    expect(response).to redirect_to("/tickets/starsandgarters")
  end

  it "shows managers the short address, with the full one under it, and encodes the short one in the QR" do
    create(:organization_role, :manager, user: admin, organization: org)
    post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
    get manage_path

    get manage_production_ticketing_path(production)
    expect(response.body).to include("http://www.example.com/t/#{link.code}", "/tickets/starsandgarters/#{production.public_key}",
                                     %(data-qr-code-url-value="http://www.example.com/t/#{link.code}"))

    get manage_ticket_listing_path(listing)
    expect(response.body).to include("http://www.example.com/t/#{link.code}/oct-17")
  end
end
