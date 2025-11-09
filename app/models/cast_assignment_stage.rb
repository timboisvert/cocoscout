class CastAssignmentStage < ApplicationRecord
  belongs_to :production
  belongs_to :cast
  belongs_to :person

  validates :production_id, :person_id, :cast_id, presence: true
  validates :person_id, uniqueness: { scope: [ :production_id, :cast_id ] }
end
