# frozen_string_literal: true

require "rails_helper"

# Smoke + cross-link coverage for the public marketing site and the
# CocoScout <-> Find a Mic integration. These pages had no specs before, so
# this also catches view/render regressions.
RSpec.describe "Public marketing site", type: :request do
  describe "GET / (two-door homepage)" do
    before { get root_path }

    it "renders the producer-first landing hero" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Run the whole production.")
      expect(response.body).to include("In one place.")
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
      expect(response.body).to include("Your whole performing life, in one place.")
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

  describe "GET /sketchfest (festival sponsor page)" do
    before { get sketchfest_path }

    it "leads with the co-branded lockup and the free CTA" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CocoScout is a Proud sponsor of Chicago SketchFest")
      expect(response.body).to include("Manage your sketch team - free")
      expect(response.body).to include(%(href="#{signup_path(ref: "sketchfest")}"))
    end

    it "states what free actually covers rather than burying the limit" do
      expect(response.body).to include("Up to #{Organization::FREE_MONTHLY_EVENT_LIMIT} shows or rehearsals a month.")
    end

    it "drops the top nav so the page has one destination" do
      # The sticky marketing header and its mobile drawer are both gone.
      expect(response.body).not_to include('data-controller="mobile-nav"')
      expect(response.body).not_to include('sticky top-0 z-30')
      # The footer stays — it carries Terms and Privacy.
      expect(response.body).to include(%(href="#{terms_path}"))
    end

    it "wires the tour modal to both the modal and product-tour controllers" do
      expect(response.body).to include('data-controller="modal product-tour"')
      expect(response.body).to include('data-modal-id="sketchfest-tour"')
      expect(response.body).to include('id="sketchfest-tour"')
    end

    it "renders the typeset wordmark until the partner artwork is committed" do
      # Falls back rather than raising on a missing asset, so the page can ship
      # before we have their logo file.
      expect(response.body).to include("Chicago SketchFest")
    end

    it "stays out of the marketing nav — it is a handed-out URL, not navigation" do
      get root_path
      expect(response.body).not_to include(%(href="#{sketchfest_path}"))
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
      expect(response.body).to include("Producer")
    end
  end
end
