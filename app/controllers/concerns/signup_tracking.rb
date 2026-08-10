# frozen_string_literal: true

# Carries two facts about a visitor from the public marketing pages to the
# moments that need them, several requests later:
#
#   session[:referral_source] — WHERE the signup came from (campaign
#   attribution, e.g. "sketchfest"). First touch wins, and it is persisted to
#   the Organization the user eventually creates.
#
#   session[:signup_intent] — WHY they're signing up ("producer" or
#   "performer"), set by the CTA they clicked. Last touch wins — someone who
#   browses the performer page and then clicks "Start free" under the Producer
#   tier means producer. Consumed once by the post-signup landing to decide
#   which side of the app greets them. "Go Pro" CTAs additionally carry
#   session[:signup_plan] / session[:signup_plan_interval] so the plan choice
#   survives to the producer setup flow.
#
# The values ride in the session rather than the query string because signup
# happens long after the link is clicked, and because a session value can't be
# forged by posting a crafted form. Only allowlisted slugs are accepted.
#
# Deliberately included only in the public-facing controllers (HomeController,
# AuthController) rather than ApplicationController: Manage::ManageController
# descends straight from ActionController::Base, so an ApplicationController
# filter wouldn't reach /manage anyway. Capture happens out here; everything
# else only ever reads the session keys.
module SignupTracking
  extend ActiveSupport::Concern

  # Campaign slugs we recognize. Anything else is ignored, so the column can't
  # be stuffed with junk (or markup) by hitting any page with ?ref=whatever.
  REFERRAL_SOURCES = %w[sketchfest].freeze

  SIGNUP_INTENTS = %w[producer performer].freeze
  SIGNUP_PLANS = %w[pro].freeze
  PLAN_INTERVALS = %w[month year].freeze

  included do
    before_action :capture_referral_source
    before_action :capture_signup_intent
  end

  private

  # First touch wins — someone who arrives via a campaign and wanders the site
  # before signing up still gets attributed to the campaign.
  def capture_referral_source
    source = params[:ref].to_s
    return unless REFERRAL_SOURCES.include?(source)

    session[:referral_source] ||= source
  end

  # Last touch wins — intent is about what the visitor wants NOW, and the most
  # recent CTA they clicked is the best evidence of that.
  def capture_signup_intent
    intent = params[:intent].to_s
    return unless SIGNUP_INTENTS.include?(intent)

    session[:signup_intent] = intent
    return unless intent == "producer" && SIGNUP_PLANS.include?(params[:plan].to_s)

    session[:signup_plan] = params[:plan].to_s
    session[:signup_plan_interval] =
      PLAN_INTERVALS.include?(params[:interval].to_s) ? params[:interval].to_s : "year"
  end
end
