class CastAssignmentStage < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :cast
  belongs_to :person
  has_one :production, through: :audition_cycle

  enum :status, { pending: 0, finalized: 1 }, default: :pending

  validates :audition_cycle_id, :person_id, :cast_id, presence: true
  validates :person_id, uniqueness: { scope: [ :audition_cycle_id, :cast_id ] }
end
