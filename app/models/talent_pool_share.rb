# frozen_string_literal: true

class TalentPoolShare < ApplicationRecord
  belongs_to :talent_pool
  belongs_to :production

  validates :talent_pool_id, uniqueness: { scope: :production_id }
  validate :same_organization

  private

  def same_organization
    return unless talent_pool && production

    pool_org = talent_pool.production&.organization_id
    prod_org = production.organization_id

    if pool_org != prod_org
      errors.add(:production, "must belong to the same organization as the talent pool's owner")
    end
  end
end
