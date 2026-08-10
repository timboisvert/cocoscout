# frozen_string_literal: true

class HomeController < ApplicationController
  include ReferralTracking

  allow_unauthenticated_access

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
  end
end
