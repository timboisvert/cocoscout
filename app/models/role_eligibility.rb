# frozen_string_literal: true

class RoleEligibility < ApplicationRecord
  belongs_to :role
  belongs_to :member, polymorphic: true

  validates :member_id, uniqueness: { scope: [ :role_id, :member_type ], message: "is already eligible for this role" }
end
