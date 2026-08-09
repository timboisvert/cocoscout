# frozen_string_literal: true

# Carries "where did this signup come from" from a public marketing page all
# the way to the created Organization, which happens several requests later
# (signup -> /my or /manage -> welcome -> new organization).
#
# The value rides in the session rather than the query string because the org
# is created long after the campaign link is clicked, and because a session
# value can't be forged by posting a crafted form.
#
# Deliberately included only in the public-facing controllers (HomeController,
# AuthController) rather than ApplicationController: Manage::ManageController
# descends straight from ActionController::Base, so an ApplicationController
# filter wouldn't reach /manage anyway. Capture happens out here; the /manage
# side only ever reads session[:referral_source].
module ReferralTracking
  extend ActiveSupport::Concern

  # Campaign slugs we recognize. Anything else is ignored, so the column can't
  # be stuffed with junk (or markup) by hitting any page with ?ref=whatever.
  REFERRAL_SOURCES = %w[sketchfest].freeze

  included do
    before_action :capture_referral_source
  end

  private

  # First touch wins — someone who arrives via a campaign and wanders the site
  # before signing up still gets attributed to the campaign.
  def capture_referral_source
    source = params[:ref].to_s
    return unless REFERRAL_SOURCES.include?(source)

    session[:referral_source] ||= source
  end
end
