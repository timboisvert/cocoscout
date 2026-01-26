# frozen_string_literal: true

class Location < ApplicationRecord
  belongs_to :organization
  has_many :shows, dependent: :restrict_with_error
  has_many :audition_sessions, dependent: :restrict_with_error
  has_many :location_spaces, dependent: :destroy

  validates :name, :address1, :city, :state, :postal_code, presence: true

  # Ensure only one location is default per organization
  before_save :ensure_single_default
  after_create :set_as_default_if_only_location

  def upcoming_shows
    shows.where("date_and_time > ?", Time.current).order(:date_and_time)
  end

  def upcoming_audition_sessions
    audition_sessions.where("start_at > ?", Time.current).order(:start_at)
  end

  def has_upcoming_events?
    upcoming_shows.exists? || upcoming_audition_sessions.exists?
  end

  def has_any_events?
    shows.exists? || audition_sessions.exists?
  end

  def full_address
    parts = [ name ]
    parts << address1 if address1.present?
    parts << address2 if address2.present?
    parts << "#{city}, #{state} #{postal_code}".strip if city.present? || state.present? || postal_code.present?
    parts.join(", ")
  end

  private

  def ensure_single_default
    return unless default?

    # Unset default for all other locations in the same organization
    Location.where(organization: organization).where.not(id: id).update_all(default: false)
  end

  def set_as_default_if_only_location
    return unless organization.locations.count == 1

    update_column(:default, true)
  end
end
