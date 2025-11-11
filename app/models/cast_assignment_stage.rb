class CastAssignmentStage < ApplicationRecord
  belongs_to :call_to_audition
  belongs_to :cast
  belongs_to :person
  has_one :production, through: :call_to_audition

  enum :status, { pending: 0, finalized: 1 }, default: :pending

  validates :call_to_audition_id, :person_id, :cast_id, presence: true
  validates :person_id, uniqueness: { scope: [ :call_to_audition_id, :cast_id ] }
end
