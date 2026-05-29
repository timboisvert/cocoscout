# frozen_string_literal: true

# Opt-in membership: this Person is part of the org's house staff and can be
# assigned to shifts. Distinct from cast assignments / talent pools.
class OrganizationStaffMember < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  has_many :staff_role_qualifications, dependent: :destroy
  has_many :house_roles, through: :staff_role_qualifications

  validates :person_id, uniqueness: { scope: :organization_id }

  scope :active, -> { where(archived_at: nil) }

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
