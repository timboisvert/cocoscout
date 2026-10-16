# frozen_string_literal: true

# What every show of a production needs: "every Halloween o' Weens show needs
# a booth tech and one security". On a production booked by a contract these
# are the extras the contract doesn't charge for ("also needed, not billed");
# the contract's own services come from the contract. See ShowServices.
class ProductionServiceNeed < ApplicationRecord
  belongs_to :production
  belongs_to :house_service

  validates :house_service_id, uniqueness: { scope: :production_id }
  validates :people_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }
  validate :same_organization

  private

  def same_organization
    return if production.nil? || house_service.nil?
    return if production.organization_id == house_service.organization_id

    errors.add(:house_service, "must belong to the production's organization")
  end
end
