# frozen_string_literal: true

# Opt-in membership: this Person is part of the org's house staff and can be
# assigned to shifts. Distinct from cast assignments / talent pools.
class OrganizationStaffMember < ApplicationRecord
  ONBOARDING_STATES = %w[added invited completed].freeze

  belongs_to :organization
  belongs_to :person
  # A staff member can report to another staff member in the same org.
  belongs_to :manager, class_name: "OrganizationStaffMember", optional: true
  has_many :reports, class_name: "OrganizationStaffMember", foreign_key: :manager_id, dependent: :nullify

  has_many :staff_role_qualifications, dependent: :destroy
  has_many :house_roles, through: :staff_role_qualifications

  validates :person_id, uniqueness: { scope: :organization_id }
  validates :onboarding_state, inclusion: { in: ONBOARDING_STATES }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :manager_in_same_org

  scope :active, -> { where(archived_at: nil) }

  # Display name: preferred first name (falls back to legal first) + last name,
  # else the linked Person's display name.
  def display_name
    first = preferred_first_name.presence || first_name.presence
    [ first, last_name.presence ].compact.join(" ").presence || person&.name
  end

  def hourly_rate_dollars
    hourly_rate_cents ? hourly_rate_cents / 100.0 : nil
  end

  def onboarding_completed?
    onboarding_state == "completed"
  end

  private

  def manager_in_same_org
    return if manager.nil?

    errors.add(:manager, "must belong to the same organization") if manager.organization_id != organization_id
  end

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
