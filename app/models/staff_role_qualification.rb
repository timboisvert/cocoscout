# frozen_string_literal: true

# Join: which house roles a given staff member is qualified to fill.
class StaffRoleQualification < ApplicationRecord
  belongs_to :organization_staff_member
  belongs_to :house_role

  validates :house_role_id, uniqueness: { scope: :organization_staff_member_id }
end
