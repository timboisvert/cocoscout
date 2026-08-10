# frozen_string_literal: true

# House staffing role definition (e.g. Bartender, FOH, Tech, Security).
# Org-scoped by default; optional location_id scopes a role to a single venue.
class HouseRole < ApplicationRecord
  belongs_to :organization
  belongs_to :location, optional: true
  has_many :shifts, dependent: :destroy
  has_many :staff_role_qualifications, dependent: :destroy

  # :house     → one shift spans the whole evening (first show start → last
  #              show end), e.g. bartender, FOH, security.
  # :show_specific → one shift per show/rehearsal, anchored to that single
  #              event, e.g. tech who must be tied to a particular show.
  enum :role_type, { house: 0, show_specific: 1 }, default: :house

  # How the work is priced. "hourly" is rate × hours; "flat" is a set amount for
  # the shift however long it runs — security who comes in for the night and
  # gets $50 whether that's three hours or five. Hours are still logged either
  # way; for a flat role they just don't decide the money.
  PAY_TYPES = %w[hourly flat].freeze

  validates :name, presence: true, length: { maximum: 100 }
  validates :default_required_count, numericality: { only_integer: true, greater_than: 0 }
  validates :default_hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :default_flat_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :pay_type, inclusion: { in: PAY_TYPES }

  # Role Call only ever looks at per-show roles, and only at the ones the org
  # actually expects on every show. A role opted out is still staffed and paid
  # like any other — it just never flags a show for being without it.
  scope :role_call, -> { active.where(role_type: role_types[:show_specific], include_in_role_call: true) }

  def role_called?
    show_specific? && include_in_role_call?
  end

  def flat?
    pay_type == "flat"
  end

  def hourly?
    !flat?
  end

  # What this role's pay looks like on screen: "$20.00/hr" or "$50.00/shift".
  # Never "/night" — plenty of shifts are matinees, load-ins or rehearsals.
  def rate_label
    cents = flat? ? default_flat_rate_cents : default_hourly_rate_cents
    return nil if cents.blank?

    "$#{format('%.2f', cents / 100.0)}#{flat? ? '/shift' : '/hr'}"
  end

  # Dollar view of the role's standard pay, for forms. nil = no default set.
  def default_hourly_rate_dollars
    default_hourly_rate_cents ? default_hourly_rate_cents / 100.0 : nil
  end

  def default_hourly_rate_dollars=(value)
    self.default_hourly_rate_cents = self.class.cents_from(value)
  end

  def default_flat_rate_dollars
    default_flat_rate_cents ? default_flat_rate_cents / 100.0 : nil
  end

  def default_flat_rate_dollars=(value)
    self.default_flat_rate_cents = self.class.cents_from(value)
  end

  def self.cents_from(value)
    return nil if value.blank?

    (value.to_s.gsub(/[^0-9.]/, "").to_f * 100).round
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
