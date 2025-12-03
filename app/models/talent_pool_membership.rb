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
    # Invalidate talent pool member counts cache
    Rails.cache.delete_matched("talent_pool_counts*#{talent_pool_id}*")
  end
end
