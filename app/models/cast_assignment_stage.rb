class CastAssignmentStage < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :talent_pool
  belongs_to :assignable, polymorphic: true
  has_one :production, through: :audition_cycle

  enum :status, { pending: 0, finalized: 1 }, default: :pending

  validates :audition_cycle_id, :assignable_id, :assignable_type, :talent_pool_id, presence: true
  validates :assignable_id, uniqueness: { scope: [ :audition_cycle_id, :talent_pool_id, :assignable_type ] }
end
