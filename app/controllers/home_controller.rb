# frozen_string_literal: true

class HomeController < ApplicationController
  include SignupTracking

  allow_unauthenticated_access

  # The app doesn't carry the marketing site: App Review rejects an app that
  # shows a website (and these pages sell Pro). Links to them open in Safari
  # (path-configuration.json); a redirect here lands on My, or the app's welcome screen.
  before_action :keep_out_of_the_app, only: %i[new_landing new_performers new_producers pricing app]

  # Use the public facing layout
  layout "home"

  # Producer-first repositioning preview (three tiers) — /new
  def new_landing; end
  def new_performers; end
  def new_producers; end

  # Free vs. Pro plan comparison
  def pricing; end

  # cocoscout.com/app. A phone is sent straight to its own store, so nobody
  # on a phone ever sees two badges; everyone else gets the page with both
  # badges and a QR code that scans to this same address.
  def app
    platform = AppStores.platform(request.user_agent)
    return redirect_to AppStores.url(platform), allow_other_host: true if platform

    @app_url = get_the_app_url
  end

  private

  def keep_out_of_the_app
    redirect_to(authenticated? ? my_dashboard_path : welcome_path) if turbo_native_app?
  end
end
