# frozen_string_literal: true

# Tells iPhones which cocoscout.com links open in the CocoScout app instead
# of Safari (universal links), and that the app may offer the passwords
# people saved for the site. Apple fetches it from
# /.well-known/apple-app-site-association: JSON, no redirect, no sign-in.
#
# Only pages the app carries: My, the Door, profiles, the cast's email links
# (can't make it, claim a role), and since 1.4 Manage, so a manager's emailed
# link opens in the app (Tim, 2026-11-22; production mode plan §8). Checkout
# stays in Safari. V1 installs, which don't carry Manage, show it in their
# own web view rather than sending it back out (path-configuration.json).
class AppleAppSiteAssociationsController < ApplicationController
  allow_unauthenticated_access

  APP_ID = "3Y9EQJP24Y.com.cocoscout.app"
  PATHS = %w[/my /my/* /door /door/* /profile /profile/* /claim/* /vacancy/* /manage /manage/*].freeze
  # Pro isn't sold in the apps, so billing opens the website (path
  # configuration "open_in": "safari"). Unclaimed here, so handing it to
  # Safari can't land it back in the app. Apple takes the first component that
  # matches, so these go first.
  EXCLUDED = %w[/manage/billing /manage/billing/* /manage/organizations/*/section/billing].freeze

  def show
    expires_in 1.hour, public: true
    render json: {
      applinks: { details: [ { appIDs: [ APP_ID ], components: EXCLUDED.map { |path| { "/" => path, "exclude" => true } } + PATHS.map { |path| { "/" => path } } } ] },
      webcredentials: { apps: [ APP_ID ] }
    }
  end
end
