# frozen_string_literal: true

require "net/http"
require "uri"

# Stores the user's "search from here" point in the session for the
# city-page distance filter. Three ways to set it:
#   1. browser geolocation — JS posts lat/lng and a label of "My location"
#   2. typed address       — server geocodes via the Census Bureau (free,
#      US-only), falls back to OSM Nominatim
#   3. clear               — drops the override and falls back to hub center
module Mics
  class OriginsController < BaseController
    USER_AGENT       = "CocoScout-Mics/1.0 (https://cocoscout.com/mics; geocode@cocoscout.com)"
    CENSUS_ENDPOINT  = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
    NOMINATIM_ENDPOINT = "https://nominatim.openstreetmap.org/search"

    def create
      lat   = params[:lat].presence&.to_f
      lng   = params[:lng].presence&.to_f
      label = params[:label].to_s.strip.presence

      # Address-based path: geocode server-side, then persist.
      if lat.nil? && (address = params[:address].to_s.strip.presence)
        result = geocode(address)
        if result
          lat   = result[:lat]
          lng   = result[:lng]
          label ||= address
        else
          return redirect_to(params[:back_to].presence || mics_home_path,
                             alert: "Couldn't find that address. Try a more specific one.")
        end
      end

      if lat.nil? || lng.nil?
        return redirect_to(params[:back_to].presence || mics_home_path,
                           alert: "Couldn't set your location.")
      end

      session[:mics_origin] = {
        "lat" => lat,
        "lng" => lng,
        "label" => label.presence || "My location",
        "kind" => params[:kind].to_s.presence || "custom"
      }
      redirect_to(params[:back_to].presence || mics_home_path,
                  notice: "Distance is now measured from #{session.dig(:mics_origin, "label")}.")
    end

    def destroy
      session.delete(:mics_origin)
      redirect_to(params[:back_to].presence || mics_home_path,
                  notice: "Distance is back to city-center.")
    end

    private

    def geocode(address)
      census_lookup(address) || nominatim_lookup(address)
    end

    def census_lookup(address)
      uri = URI(CENSUS_ENDPOINT)
      uri.query = URI.encode_www_form(
        address: address, benchmark: "Public_AR_Current", format: "json"
      )
      res = http_get(uri)
      return nil unless res.is_a?(Net::HTTPSuccess)
      match = (JSON.parse(res.body).dig("result", "addressMatches") || []).first
      return nil unless match && match["coordinates"]
      { lat: match["coordinates"]["y"].to_f, lng: match["coordinates"]["x"].to_f }
    rescue StandardError => e
      Rails.logger.warn "Census geocode failed: #{e.message}"
      nil
    end

    def nominatim_lookup(address)
      uri = URI(NOMINATIM_ENDPOINT)
      uri.query = URI.encode_www_form(
        q: address, format: "json", limit: 1, addressdetails: 0, countrycodes: "us"
      )
      res = http_get(uri)
      return nil unless res.is_a?(Net::HTTPSuccess)
      hit = JSON.parse(res.body).first
      return nil unless hit && hit["lat"].present? && hit["lon"].present?
      { lat: hit["lat"].to_f, lng: hit["lon"].to_f }
    rescue StandardError => e
      Rails.logger.warn "Nominatim geocode failed: #{e.message}"
      nil
    end

    def http_get(uri)
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = USER_AGENT
      req["Accept"]     = "application/json"
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
    end
  end
end
