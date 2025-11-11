class AuditionEmailAssignment < ApplicationRecord
  belongs_to :call_to_audition
  belongs_to :person

  validates :person_id, uniqueness: { scope: :call_to_audition_id }
end
