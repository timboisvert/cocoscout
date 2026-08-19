# frozen_string_literal: true

# Join: which house roles a given staff member is qualified to fill, and what
# they're paid for that role (nil = fall back to the member's default rate).
class StaffRoleQualification < ApplicationRecord
  belongs_to :organization_staff_member
  belongs_to :house_role

  validates :house_role_id, uniqueness: { scope: :organization_staff_member_id }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def hourly_rate_dollars
    hourly_rate_cents ? hourly_rate_cents / 100.0 : nil
  end

  # This person's per-shift amount for a flat-pay role (see HouseRole#flat?).
  def flat_rate_dollars
    flat_rate_cents ? flat_rate_cents / 100.0 : nil
  end
end
