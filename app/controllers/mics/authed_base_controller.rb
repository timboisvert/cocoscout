# frozen_string_literal: true

# Producer/claim/submission/challenge controllers — auth required. Keeps
# the public BaseController's overrides while restoring authentication.
module Mics
  class AuthedBaseController < ApplicationController
    before_action :suppress_app_chrome

    helper_method :hub_for, :city_state_from_slug

    private

    def suppress_app_chrome
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
    end

    def city_state_from_slug(slug)
      return [ nil, nil ] if slug.blank?
      if (hub = CityHub.find_by(slug: slug))
        return [ hub.name, hub.state ]
      end
      parts = slug.split("-")
      if parts.length >= 2 && parts.last.length == 2
        [ parts[0..-2].map(&:capitalize).join(" "), parts.last.upcase ]
      else
        [ parts.map(&:capitalize).join(" "), nil ]
      end
    end

    def hub_for(city, state)
      return nil if city.blank? || state.blank?
      CityHub.for(city, state)
    end

    def current_user
      Current.user
    end

    def load_mic
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end
  end
end
