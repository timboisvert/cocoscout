# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics public flow", type: :request do
  let(:venue) { create(:venue, name: "Cafe Mustache", city: "Chicago", state: "IL", neighborhood: "Logan Square") }
  let!(:mic)  { create(:mic, venue: venue, name: "Mustache Mic") }

  describe "GET /mics" do
    it "renders the homepage with the city link" do
      get mics_home_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Find an open mic tonight")
      expect(response.body).to include("Chicago, IL")
    end
  end

  describe "GET /mics/:city_slug" do
    it "lists active mics in that city" do
      get mics_city_path("chicago-il")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mustache Mic")
      expect(response.body).to include("application/ld+json")
    end
  end

  describe "city page with ?view=map" do
    it "renders the map view with mics data attribute when geocoded" do
      venue.update!(lat: 41.9, lng: -87.7, geocoded_at: Time.current)
      get mics_city_path("chicago-il", view: "map")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"mics-map\"")
    end

    it "still renders the map shell when nothing is geocoded" do
      get mics_city_path("chicago-il", view: "map")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Awaiting geocode").or include("not been geocoded")
    end

    it "legacy /map URL redirects to ?view=map" do
      get mics_city_map_path("chicago-il")
      expect(response).to redirect_to(mics_city_path("chicago-il", view: "map"))
    end
  end

  describe "Hub rollup" do
    let!(:hub)      { create(:city_hub, :active, slug: "chicago-il", name: "Chicago", state: "IL", timezone: "America/Chicago") }
    let!(:suburb_venue) { create(:venue, name: "Suburb Spot", city: "Forest Park", state: "IL", city_hub: hub) }
    let!(:suburb_mic)   { create(:mic, venue: suburb_venue, name: "Suburb Mic") }

    it "shows a hub satellite city's mic on the hub page" do
      get mics_city_path("chicago-il")
      expect(response.body).to include("Suburb Mic")
    end

    it "301-redirects the satellite city slug to the hub slug" do
      get mics_city_path("forest-park-il")
      expect(response).to redirect_to(mics_city_path("chicago-il"))
      expect(response).to have_http_status(:moved_permanently)
    end
  end

  describe "GET /mics/:city_slug/tonight" do
    it "renders the bucket view" do
      get mics_city_tonight_path("chicago-il")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tonight")
    end
  end

  describe "GET /mics/m/:slug" do
    it "renders the mic detail page with JSON-LD event payload" do
      get mics_detail_path(mic.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mustache Mic")
      expect(response.body).to include("Cafe Mustache")
      expect(response.body).to include("application/ld+json")
      expect(response.body).to include("schema.org")
    end

    it "404s for an unknown slug" do
      get mics_detail_path("nope-nope-nope")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /mics/sitemap.xml" do
    it "renders the sitemap index" do
      get mics_sitemap_path
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml").or eq("text/xml")
      expect(response.body).to include("<urlset").or include("<sitemapindex")
    end
  end

  describe "GET /mics/search" do
    it "returns results when query matches" do
      get mics_search_path, params: { q: "mustache" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mustache Mic")
    end

    it "asks for more characters when query is blank" do
      get mics_search_path, params: { q: "" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Type at least two characters").or include("Search")
    end
  end
end
