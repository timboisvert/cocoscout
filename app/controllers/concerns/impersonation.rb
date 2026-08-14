# frozen_string_literal: true

# Who, if anyone, is impersonating the currently signed-in user.
#
# Included by both controller roots (ApplicationController and
# Manage::ManageController, which descends straight from ActionController::Base)
# so controllers and views everywhere share one definition.
module Impersonation
  extend ActiveSupport::Concern

  included do
    helper_method :impersonating?, :impersonator_user_id
  end

  private

  # The session row is authoritative: it is found via the *permanent* signed
  # :session_id cookie, so it lives exactly as long as the impersonated login
  # does. The Rails session and the signed :impersonator_user_id cookie are
  # browser-session cookies — mobile browsers discard them on force-quit or
  # memory pressure while the permanent login cookie survives, which is how the
  # banner used to disappear mid-impersonation. They stay here only as a
  # fallback for impersonations that were already running before this change.
  def impersonator_user_id
    Current.session&.impersonator_user_id ||
      cookies.signed[:impersonator_user_id].presence ||
      session[:user_doing_the_impersonating].presence
  end

  def impersonating?
    # A stale impersonator cookie can outlive the impersonated login (e.g. on
    # the signed-out /signin page) — no signed-in user means no impersonation.
    Current.user.present? && impersonator_user_id.present?
  end
end
