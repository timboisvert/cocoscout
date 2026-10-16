# frozen_string_literal: true

# A role that does a service: ticket taking is done by Front of House and by
# House Manager. Staffing the service offers people who hold one of them.
class HouseServiceRole < ApplicationRecord
  belongs_to :house_service
  belongs_to :house_role

  validates :house_role_id, uniqueness: { scope: :house_service_id }
  validate :same_organization

  private

  def same_organization
    return if house_service.nil? || house_role.nil?
    return if house_service.organization_id == house_role.organization_id

    errors.add(:house_role, "must belong to the same organization")
  end
end
