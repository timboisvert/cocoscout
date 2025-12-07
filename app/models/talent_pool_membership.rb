class TalentPoolMembership < ApplicationRecord
  belongs_to :talent_pool, touch: true
  belongs_to :member, polymorphic: true

  validates :talent_pool, presence: true
  validates :member, presence: true
  validates :member_id, uniqueness: { scope: [ :talent_pool_id, :member_type ] }
end
