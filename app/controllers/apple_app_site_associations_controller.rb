# frozen_string_literal: true

# Tells iPhones which cocoscout.com links open in the CocoScout app instead
# of Safari (universal links), and that the app may offer the passwords
# people saved for the site. Apple fetches it from
# /.well-known/apple-app-site-association: JSON, no redirect, no sign-in.
#
# Only pages the app carries: My, the Door, profiles, and the cast's email
# links (can't make it, claim a role). Manage and checkout stay in Safari.
class AppleAppSiteAssociationsController < ApplicationController
  allow_unauthenticated_access

  APP_ID = "3Y9EQJP24Y.com.cocoscout.app"
  PATHS = %w[/my /my/* /door /door/* /profile /profile/* /claim/* /vacancy/*].freeze

  def show
    expires_in 1.hour, public: true
    render json: {
      applinks: { details: [ { appIDs: [ APP_ID ], components: PATHS.map { |path| { "/" => path } } } ] },
      webcredentials: { apps: [ APP_ID ] }
    }
  end
end
