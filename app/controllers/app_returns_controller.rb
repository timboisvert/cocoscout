# frozen_string_literal: true

# The way back into the iOS app from a page it opened in its own secure sheet
# (Stripe's bank setup, for one). The sheet has none of the app's cookies, so
# Stripe's return address can't be a signed-in page; it comes here instead,
# and this hands the app a cocoscout:// link naming the page to open, which
# the app then loads signed in (ios/CocoScout/Routing/StripeSheet.swift).
# Only pages in My, so this never sends anyone anywhere else.
class AppReturnsController < ApplicationController
  allow_unauthenticated_access

  APP_SCHEME = "cocoscout"
  ALLOWED_PATH = %r{\A/my(/[\w\-/]*)?\z}

  def show
    path = params[:to].to_s
    path = "/my" unless path.match?(ALLOWED_PATH)
    redirect_to "#{APP_SCHEME}://open?path=#{CGI.escape(path)}", allow_other_host: true
  end
end
