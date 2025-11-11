class AuditionEmailAssignment < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :person

  validates :person_id, uniqueness: { scope: :audition_cycle_id }
end
