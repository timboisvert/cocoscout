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

    it "sells ticketing as a headline feature at the real per-ticket fee" do
      # The figure is read from TicketPricing so the pitch can't drift from checkout.
      expect(response.body).to include("Sell tickets for #{TicketPricing::PLATFORM_FEE_CENTS}¢ a ticket.")
      expect(response.body).to include("Instead of a ticketing site")
      expect(response.body).to include("for free tickets, comps &amp; cash at the door")
      expect(response.body).to include("standard card processing, nothing added")
      expect(response.body).not_to include("2.9%") # rates differ by channel; never quote one
    end
  end

  describe "GET /for-producers" do
    it "positions CocoScout as the producer operating platform" do
      get producers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("operating platform for")
      expect(response.body).to include(%(href="#{mics_home_path}")) # shared header bridge
    end

    it "leads the feature areas with ticketing at 50¢ a ticket" do
      get producers_path
      expect(response.body).to include("Sell tickets for #{TicketPricing::PLATFORM_FEE_CENTS}¢ a ticket.")
      expect(response.body).to include("Instead of a ticketing site")
      expect(response.body).to include("with our 50¢ always returned")
    end
  end

  describe "GET /pricing" do
    before { get pricing_path }

    it "states the ticketing fee and that free tickets are free" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("50¢ a ticket. Free tickets are free.")
      expect(response.body).to include("What does ticketing cost?")
      expect(response.body).to include("Do you take a cut of the card processing?")
    end

    it "names advanced ticketing as an Enterprise direction, not a Pro feature" do
      expect(response.body).to include("Advanced ticketing: reserved seating, subscriptions, group sales")
      expect(response.body).to include("Patron CRM &amp; donations")
      # Nothing here is built yet, so the comparison table keeps ticketing as one row.
      expect(response.body).not_to include("Reserved seating</td>")
    end

    it "no longer claims there is no per-transaction cut, which the ticket fee contradicts" do
      expect(response.body).not_to include("no per-transaction cut")
      expect(response.body).to include("no cut of what you pay out")
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

  describe "GET /sketchfest (taken down)" do
    it "sends old flyer links to the home page" do
      get "/sketchfest"
      expect(response).to redirect_to("/")
      get "/sketchfest/qr"
      expect(response).to redirect_to("/")
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
    # One single-column shell (shared/auth/_shell); the pitch lives on the
    # marketing pages, not here.
    it "sign in renders as one screen for signing in and creating an account" do
      get signin_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in or create an account", "Email address")
    end

    it "sign up leads to the same screen" do
      get signup_path
      expect(response).to redirect_to(signin_path)
    end
  end
end
