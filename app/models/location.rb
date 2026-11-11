# frozen_string_literal: true

class Location < ApplicationRecord
  belongs_to :organization
  has_many :shows, dependent: :restrict_with_error
  has_many :audition_sessions, dependent: :restrict_with_error
  has_many :location_spaces, dependent: :destroy

  validates :name, :address1, :city, :state, :postal_code, presence: true

  # Archived (2026-11-11): a location the organization no longer uses. It
  # and its rooms leave the locations list and every picker for something
  # new, and nothing that already points at it changes: old shows, rentals,
  # contracts and public pages keep its name and address.
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  # What a picker offers: the locations in use, plus whichever ones the
  # record being edited already points at, so saving an old show never
  # blanks its location.
  scope :pickable, ->(*keep_ids) { where(archived_at: nil).or(where(id: keep_ids.flatten.compact)) }

  # An archived location is never the default.
  before_save { self.default = false if archived? }
  # Ensure only one location is default per organization
  before_save :ensure_single_default
  after_create :set_as_default_if_only_location

  def upcoming_shows
    shows.where("date_and_time > ?", Time.current).order(:date_and_time)
  end

  def upcoming_audition_sessions
    audition_sessions.where("start_at > ?", Time.current).order(:start_at)
  end

  # Every location id named anywhere in a contract's draft data (booking
  # rules, staged bookings), for `pickable` to keep.
  def self.ids_named_in(data)
    case data
    when Hash then data.flat_map { |key, value| key.to_s == "location_id" ? [ value.presence&.to_i ] : ids_named_in(value) }.compact
    when Array then data.flat_map { |value| ids_named_in(value) }
    else []
    end
  end

  def archived?
    archived_at.present?
  end

  # The default passes to the organization's oldest other location in use.
  def archive!
    # with_lock reloads first, so a stale copy can't keep a default it was
    # handed since it was read.
    with_lock do
      next if archived?

      was_default = default?
      update!(archived_at: Time.current, default: false)
      organization.locations.active.order(:created_at).first&.update!(default: true) if was_default
    end
  end

  # Back in the list and the pickers; the default again only when the
  # organization has no other.
  def restore!
    with_lock do
      update!(archived_at: nil, default: !organization.locations.active.exists?(default: true)) if archived?
    end
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
    return unless organization.locations.active.count == 1

    update_column(:default, true)
  end
end
