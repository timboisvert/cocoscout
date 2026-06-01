# frozen_string_literal: true

# The curated layer on top of a city listing page in the Open Mic Finder.
#
# A city listing page exists for ANY city with at least one Mic — derived
# from `Venue.city + state`, no CityHub required. The CityHub row only
# materializes for **promoted** cities, and is what unlocks intro markdown,
# featured-mic curation, default-radius tuning, and editor memberships.
class CityHub < ApplicationRecord
  has_many :city_hub_memberships, dependent: :destroy
  has_many :memberships, class_name: "CityHubMembership"
  has_many :members, through: :memberships, source: :user
  has_many :venues, dependent: :nullify
  has_many :mics, through: :venues

  enum :status, {
    draft: 0,
    active: 1,
    archived: 2
  }, prefix: :hub

  def editor?(user)
    return false unless user
    memberships.where(user_id: user.id, role: CityHubMembership.roles[:editor]).exists?
  end

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ },
                   length: { maximum: 80 }
  validates :name, :state, presence: true

  # Looks up the curated hub for a given city/state, if there is one.
  def self.for(city, state)
    where("LOWER(name) = LOWER(?) AND state = ?", city, state).first
  end

  def to_param
    slug
  end
end
