# frozen_string_literal: true

class HomeController < ApplicationController
  include SignupTracking

  allow_unauthenticated_access

  # The app doesn't carry the marketing site: App Review rejects an app that
  # shows a website (and these pages sell Pro). Links to them open in Safari
  # (path-configuration.json); a redirect here lands on My, or sign-in.
  before_action :keep_out_of_the_app, only: %i[new_landing new_performers new_producers pricing sketchfest]

  # Use the public facing layout
  layout "home"

  # Producer-first repositioning preview (three tiers) — /new
  def new_landing; end
  def new_performers; end
  def new_producers; end

  # Free vs. Pro plan comparison
  def pricing; end

  # CocoScout x Chicago SketchFest sponsor page — /sketchfest.
  #
  # Landing here counts as the referral even without ?ref=, so someone who
  # already has an account and signs in (rather than signing up) still gets
  # attributed when they later create an organization.
  def sketchfest
    session[:referral_source] ||= "sketchfest"
    # The whole page is a producer pitch, so landing here is producer intent —
    # but don't clobber a choice an earlier CTA click already made.
    session[:signup_intent] ||= "producer"
  end

  # QR code for /sketchfest, for pasting into flyers and decks. Viewing this
  # page is not itself a referral — scanning the code lands on /sketchfest,
  # which does the attribution.
  def sketchfest_qr; end

  private

  def keep_out_of_the_app
    redirect_to(authenticated? ? my_dashboard_path : signin_path) if turbo_native_app?
  end
end
