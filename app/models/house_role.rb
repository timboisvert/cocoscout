# frozen_string_literal: true

# House staffing role definition (e.g. Bartender, FOH, Tech, Security).
# Org-scoped by default; optional location_id scopes a role to a single venue.
class HouseRole < ApplicationRecord
  belongs_to :organization
  belongs_to :location, optional: true
  has_many :shifts, dependent: :destroy
  has_many :staff_role_qualifications, dependent: :destroy
  has_many :qualified_staff_members, through: :staff_role_qualifications, source: :organization_staff_member

  validates :name, presence: true, length: { maximum: 100 }
  validates :default_required_count, numericality: { only_integer: true, greater_than: 0 }

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
