# frozen_string_literal: true

# Geocodes a Venue using the US Census Bureau's public geocoder. Free,
# no API key, no rate limits worth respecting, US-only. Falls back to
# OSM Nominatim when Census returns no match (small towns + suburbs
# sometimes miss Census's address parser).
class VenueGeocodeJob < ApplicationJob
  queue_as :default

  USER_AGENT       = "CocoScout-Mics/1.0 (https://cocoscout.com/mics; geocode@cocoscout.com)"
  CENSUS_ENDPOINT  = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
  NOMINATIM_ENDPOINT = "https://nominatim.openstreetmap.org/search"
  THROTTLE_KEY     = "mics:geocode:nominatim:next_allowed_at"

  def perform(venue_id)
    venue = Venue.find_by(id: venue_id)
    return unless venue
    return if venue.geocoded?
    return if venue.address1.blank?

    address = [ venue.address1, venue.address2, venue.city, venue.state, venue.postal_code ]
              .map(&:presence).compact.join(", ")

    coords = census_lookup(address) || nominatim_lookup(address)

    if coords
      venue.update!(lat: coords[:lat], lng: coords[:lng],
                    geocoded_at: Time.current, geocode_error: nil)
    else
      venue.update!(geocode_error: "no_match", geocoded_at: Time.current)
    end
  rescue StandardError => e
    Rails.logger.warn("VenueGeocodeJob failed for venue=#{venue_id}: #{e.message}")
    venue&.update(geocode_error: e.class.name) if venue
  end

  private

  def census_lookup(address)
    uri = URI(CENSUS_ENDPOINT)
    uri.query = URI.encode_www_form(
      address: address, benchmark: "Public_AR_Current", format: "json"
    )
    res = http_get(uri)
    return nil unless res.is_a?(Net::HTTPSuccess)

    matches = JSON.parse(res.body).dig("result", "addressMatches") || []
    return nil if matches.empty?
    coord = matches.first["coordinates"] || {}
    { lat: coord["y"].to_f, lng: coord["x"].to_f }
  rescue StandardError => e
    Rails.logger.warn("Census geocode failed: #{e.message}")
    nil
  end

  def nominatim_lookup(address)
    wait_for_throttle_window

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
    Rails.logger.warn("Nominatim geocode failed: #{e.message}")
    nil
  end

  def http_get(uri)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"]     = "application/json"
    Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                    open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
  end

  # Nominatim: cross-worker throttle when we fall back to it.
  def wait_for_throttle_window
    loop do
      next_at = Rails.cache.read(THROTTLE_KEY)
      now = Time.current
      if next_at.nil? || next_at <= now
        Rails.cache.write(THROTTLE_KEY, now + 1.05.seconds, expires_in: 30.seconds)
        return
      end
      sleep([ next_at - now, 0.1 ].max)
    end
  end
end
