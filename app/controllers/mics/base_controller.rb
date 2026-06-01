# frozen_string_literal: true

# Shared base for the public Mics Finder controllers.
# - No auth required: the whole finder is public.
# - Skips the default sidebar/dashboard before_actions where they're set.
module Mics
  class BaseController < ApplicationController
    allow_unauthenticated_access

    # Try to resume the session even though auth isn't required, so
    # `Current.user` is populated when a signed-in visitor browses public
    # mics pages (used for Favorite/Alert/Vote attribution).
    before_action :resume_session

    # The Mics Finder is its own surface — don't show the talent
    # dashboard sidebar even for signed-in users.
    before_action :suppress_app_chrome

    # Helpers for slug → city lookups, used by both cities & detail controllers.
    helper_method :hub_for, :city_state_from_slug

    private

    def suppress_app_chrome
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
    end

    # `chicago-il` → ["Chicago", "IL"]. Also accepts `chicago` (assumes IL
    # for the launch — could fall back to a CityHub lookup when one exists).
    def city_state_from_slug(slug)
      return [ nil, nil ] if slug.blank?

      if (hub = CityHub.find_by(slug: slug))
        return [ hub.name, hub.state ]
      end

      parts = slug.split("-")
      if parts.length >= 2 && parts.last.length == 2
        state = parts.last.upcase
        city  = parts[0..-2].map(&:capitalize).join(" ")
        [ city, state ]
      else
        [ parts.map(&:capitalize).join(" "), nil ]
      end
    end

    def hub_for(city, state)
      return nil if city.blank? || state.blank?
      CityHub.for(city, state)
    end
  end
end
