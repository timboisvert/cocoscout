# frozen_string_literal: true

# House staffing role definition (e.g. Bartender, FOH, Tech, Security).
# Org-scoped by default; optional location_id scopes a role to a single venue.
class HouseRole < ApplicationRecord
  belongs_to :organization
  belongs_to :location, optional: true
  has_many :shifts, dependent: :destroy
  has_many :staff_role_qualifications, dependent: :destroy
  has_many :qualified_staff_members, through: :staff_role_qualifications, source: :organization_staff_member

  # :house     → one shift spans the whole evening (first show start → last
  #              show end), e.g. bartender, FOH, security.
  # :show_specific → one shift per show/rehearsal, anchored to that single
  #              event, e.g. tech who must be tied to a particular show.
  enum :role_type, { house: 0, show_specific: 1 }, default: :house

  validates :name, presence: true, length: { maximum: 100 }
  validates :default_required_count, numericality: { only_integer: true, greater_than: 0 }
  validates :default_hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Dollar view of the role's standard pay, for forms. nil = no default set.
  def default_hourly_rate_dollars
    default_hourly_rate_cents ? default_hourly_rate_cents / 100.0 : nil
  end

  def default_hourly_rate_dollars=(value)
    self.default_hourly_rate_cents =
      if value.blank?
        nil
      else
        (value.to_s.gsub(/[^0-9.]/, "").to_f * 100).round
      end
  end

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :name) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end
end
