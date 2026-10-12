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

  # The session row is the only source: it is found via the *permanent* signed
  # :session_id cookie, so it lives exactly as long as the impersonated login
  # does, and a new sign-in starts a row without one. The old browser-cookie
  # copies (a signed :impersonator_user_id cookie, the Rails session) outlived
  # a sign-out, so whoever signed in next on that browser got a Stop button
  # that signed them in as the superadmin. Never read them again.
  def impersonator_user_id
    Current.session&.impersonator_user_id
  end

  def impersonating?
    # A stale impersonator cookie can outlive the impersonated login (e.g. on
    # the signed-out /signin page) — no signed-in user means no impersonation.
    Current.user.present? && impersonator_user_id.present?
  end
end
