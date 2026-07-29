# frozen_string_literal: true

class CastAssignmentStage < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :talent_pool
  belongs_to :assignable, polymorphic: true
  has_one :production, through: :audition_cycle

  enum :status, { pending: 0, finalized: 1 }, default: :pending
  enum :decision_type, { cast: 0, rejected: 1 }, default: :cast

  # Archived stages are decisions the manager has "cleared" off the casting board.
  # They keep their history but no longer appear in the buckets or auditionee list.
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  validates :audition_cycle_id, :assignable_id, :assignable_type, :talent_pool_id, presence: true
  validates :assignable_id, uniqueness: { scope: %i[audition_cycle_id talent_pool_id assignable_type] }
end
