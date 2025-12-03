class TalentPoolMembership < ApplicationRecord
  belongs_to :talent_pool
  belongs_to :member, polymorphic: true

  validates :talent_pool, presence: true
  validates :member, presence: true
  validates :member_id, uniqueness: { scope: [ :talent_pool_id, :member_type ] }

  # Cache invalidation
  after_commit :invalidate_talent_pool_caches

  private

  def invalidate_talent_pool_caches
    return unless talent_pool_id
    # Note: talent_pool_counts uses key versioning with talent_pool_memberships.maximum(:updated_at)
    # so it auto-invalidates when membership updated_at changes
  end
end
