# frozen_string_literal: true

require "rails_helper"

# Smoke + cross-link coverage for the public marketing site and the
# CocoScout <-> Find a Mic integration. These pages had no specs before, so
# this also catches view/render regressions.
RSpec.describe "Public marketing site", type: :request do
  describe "GET / (two-door homepage)" do
    before { get root_path }

    it "renders with both audience doors and the new positioning" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("I run shows")
      expect(response.body).to include("I perform")
      expect(response.body).to include("operating platform")
    end

    it "links to Find a Mic and includes the mobile nav drawer" do
      expect(response.body).to include(%(href="#{mics_home_path}"))
      expect(response.body).to include('data-controller="mobile-nav"')
      expect(response.body).to include('data-action="click->mobile-nav#toggle"')
    end

    it "no longer leads with the old performer-centric headline" do
      expect(response.body).not_to include("Where performers and<br>productions connect")
    end
  end

  describe "GET /for-producers" do
    it "positions CocoScout as the producer operating platform" do
      get producers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("operating platform for")
      expect(response.body).to include(%(href="#{mics_home_path}")) # shared header bridge
    end
  end

  describe "GET /for-performers" do
    it "leads with discovery and cross-links Find a Mic" do
      get performers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Find where to perform")
      expect(response.body).to include(%(href="#{mics_home_path}"))
      expect(response.body).not_to include("Your talent deserves")
    end
  end

  describe "GET /mics (Find a Mic identity + CocoScout bridge)" do
    it "reads as its own site and bridges back to CocoScout in the footer" do
      get mics_home_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Find a Mic")
      expect(response.body).to include("by CocoScout")
      # The producer bridge lives in the footer (not the top nav), as an
      # absolute cocoscout.com link.
      expect(response.body).to include("cocoscout.com/for-producers")
    end
  end

  describe "auth pages" do
    it "sign in renders persona cards linking to Find a Mic" do
      get signin_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{mics_home_path}"))
    end

    it "sign up renders" do
      get signup_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("run shows")
    end
  end
end
