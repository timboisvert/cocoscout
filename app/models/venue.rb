# frozen_string_literal: true

# A public, deduplicated venue used by the Open Mic Finder. Distinct from
# `Location`, which is org-scoped private space.
class Venue < ApplicationRecord
  belongs_to :city_hub, optional: true
  has_many :mics, dependent: :restrict_with_error

  enum :venue_type, {
    other: 0,
    bar: 1,
    coffee_shop: 2,
    comedy_club: 3,
    basement: 4,
    theater: 5,
    online: 6
  }

  validates :name, presence: true, length: { maximum: 200 }
  validates :city, :state, :country, presence: true

  # On address change (or initial create with an address), enqueue a
  # geocoder job. No-op when we already have coordinates.
  after_commit :enqueue_geocode_if_needed, on: %i[create update]

  # Useful at render-time to print "Lincoln Square, Chicago, IL".
  def neighborhood_city
    [ neighborhood.presence, city ].compact.join(", ")
  end

  def full_address
    [ address1.presence, address2.presence, city, state, postal_code.presence ].compact.join(", ")
  end

  def geocoded?
    lat.present? && lng.present?
  end

  def needs_geocode?
    !geocoded? && geocode_error.blank? && address1.present?
  end

  private

  def enqueue_geocode_if_needed
    return unless needs_geocode?
    # Skip in test to avoid hitting the network from specs; production +
    # development still enqueue the job via Solid Queue.
    return if Rails.env.test?
    VenueGeocodeJob.perform_later(id)
  end
end
