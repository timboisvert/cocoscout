# frozen_string_literal: true

# End-to-end pre-launch checklist driven by the Mics build plan.
# Validates the things we can validate programmatically; the items that
# require a real device (push) or external graders (Lighthouse, Google
# Rich Results) are listed in the build summary instead.

require "rails_helper"
require "icalendar"
require "nokogiri"

RSpec.describe "Mics pre-launch checklist", type: :request do
  let!(:venue) { create(:venue, :geocoded, name: "Cafe Mustache", neighborhood: "Logan Square", city: "Chicago", state: "IL") }
  let!(:mic)   { create(:mic, venue: venue, name: "Mustache Mic", day_of_week: 2,
                              starts_local_time: Time.zone.parse("20:00"), blurb: "Friendly weekly bucket draw.") }
  let!(:hub)   { create(:city_hub, :active, slug: "chicago-il", name: "Chicago", state: "IL", timezone: "America/Chicago") }

  describe "robots.txt + sitemap" do
    it "robots.txt allows /mics/ and points at the sitemap" do
      body = File.read(Rails.root.join("public/robots.txt"))
      expect(body).to include("Allow: /mics")
      expect(body).to match(%r{Sitemap:\s+https?://[^\s]+/mics/sitemap\.xml})
    end

    it "sitemap renders valid XML with the city sitemap entry" do
      get mics_sitemap_path
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::XML(response.body) { |c| c.strict }
      expect(doc.errors).to be_empty
      expect(doc.root.name).to eq("sitemapindex")
      expect(response.body).to include("sitemap-chicago-il.xml")
    end

    it "city sitemap includes the mic detail URL" do
      get mics_sitemap_city_path("chicago-il")
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::XML(response.body) { |c| c.strict }
      expect(doc.errors).to be_empty
      expect(response.body).to include(mic.slug)
    end
  end

  describe "JSON-LD payloads validate as JSON + have required schema.org keys" do
    def jsonld_blocks(body)
      Nokogiri::HTML(body).css('script[type="application/ld+json"]').map { |s| JSON.parse(s.text) }
    end

    it "the city page emits ItemList + BreadcrumbList" do
      get mics_city_path("chicago-il")
      blocks = jsonld_blocks(response.body)
      types = blocks.map { |b| b["@type"] }
      expect(types).to include("ItemList")
      expect(types).to include("BreadcrumbList")
    end

    it "the mic detail page emits Event + BreadcrumbList with eventStatus" do
      get mics_detail_path(mic.slug)
      blocks = jsonld_blocks(response.body)
      event = blocks.detect { |b| b["@type"] == "Event" }
      expect(event).not_to be_nil
      expect(event["eventStatus"]).to start_with("https://schema.org/Event")
      expect(event["location"]["@type"]).to eq("Place")
      breadcrumb = blocks.detect { |b| b["@type"] == "BreadcrumbList" }
      expect(breadcrumb["itemListElement"].size).to be >= 2
    end
  end

  describe "OG + Twitter meta tags render on shareable surfaces" do
    %i[homepage city detail].each do |surface|
      it "#{surface} has og:title, og:description, twitter:card" do
        path = case surface
        when :homepage then mics_home_path
        when :city     then mics_city_path("chicago-il")
        when :detail   then mics_detail_path(mic.slug)
        end
        get path
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('meta[property="og:title"]')).not_to be_nil
        expect(doc.at('meta[property="og:description"]')).not_to be_nil
        expect(doc.at('meta[name="twitter:card"]')).not_to be_nil
        expect(doc.at('link[rel="canonical"]')).not_to be_nil
      end
    end
  end

  describe "Nominatim attribution is rendered where venue is geocoded" do
    it "is present on the mic detail page" do
      get mics_detail_path(mic.slug)
      expect(response.body).to include("OpenStreetMap")
    end

    it "is present on the city page footer (Map data ©)" do
      get mics_city_path("chicago-il")
      expect(response.body).to include("OpenStreetMap")
    end
  end

  describe "Healthcheck" do
    it "/up returns 200 OK" do
      get "/up"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OK")
    end
  end

  describe "Claim → adjudicate → producer dashboard happy path" do
    let(:user)  { create(:user, password: "Password123!") }
    let(:admin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }

    it "runs end-to-end" do
      post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
      post mics_create_claim_path(mic.slug), params: { mic_claim: { role: "producer", proof: { email: "no@example.com" } } }
      claim = MicClaim.last
      expect(claim.status).to eq("pending")

      # Admin approves.
      delete signout_path
      post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
      post mics_approve_claim_path(claim.id)
      claim.reload
      expect(claim.status).to eq("approved")
      expect(MicProducer.where(mic: mic, user: user).exists?).to be(true)
      expect(mic.reload.lead_producer_user_id).to eq(user.id)

      # Producer can see their dashboard.
      delete signout_path
      post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
      get mics_owner_mic_path(mic.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Migration wizard happy path on a fresh account" do
    let(:user) { create(:user, password: "Password123!") }

    it "creates Org → Production → Shows → SignUpForm and links the mic" do
      create(:mic_producer, mic: mic, user: user, role: :producer)
      post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }

      expect {
        post mics_owner_perform_migrate_path(mic.slug)
      }.to change { Organization.count }.by(1)
        .and change { Production.count }.by(1)
        .and change { SignUpForm.count }.by(1)

      mic.reload
      expect(mic.production_id).not_to be_nil
      expect(mic.production.shows.where(event_type: :open_mic)).not_to be_empty
    end
  end
end
