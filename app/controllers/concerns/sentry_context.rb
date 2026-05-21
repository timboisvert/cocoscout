# frozen_string_literal: true

# Shared Sentry context for all controllers. Sets the user, org/production
# tags, and exposes a helper for stashing per-request context that will be
# attached to any Sentry event raised during the rest of the request.
#
# Included by ApplicationController and Manage::ManageController (which
# inherits directly from ActionController::Base, not ApplicationController,
# so it doesn't automatically pick up application-controller helpers).
module SentryContext
  extend ActiveSupport::Concern

  included do
    before_action :set_sentry_context
  end

  private

  def set_sentry_context
    return unless defined?(Sentry)

    if Current.user.present?
      Sentry.set_user(
        id: Current.user.id,
        email: Current.user.email_address,
        superadmin: !!Current.user.superadmin?
      )
    end

    tags = {
      controller: self.class.name,
      action: action_name
    }
    tags[:organization_id] = Current.organization.id if Current.respond_to?(:organization) && Current.organization
    tags[:production_id] = Current.production.id if Current.respond_to?(:production) && Current.production
    Sentry.set_tags(tags)

    if Current.respond_to?(:organization) && Current.organization
      Sentry.set_context("organization", {
        id: Current.organization.id,
        name: Current.organization.name
      })
    end
    if Current.respond_to?(:production) && Current.production
      Sentry.set_context("production", {
        id: Current.production.id,
        name: Current.production.name
      })
    end
  end

  # Stash arbitrary context for the rest of the request. Safe when Sentry
  # isn't loaded (e.g. dev/test).
  def sentry_context(name, hash)
    return unless defined?(Sentry)
    Sentry.set_context(name.to_s, hash)
  end
end
