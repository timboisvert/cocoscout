class QuestionnaireInvitation < ApplicationRecord
  belongs_to :questionnaire
  belongs_to :person

  validates :questionnaire, presence: true
  validates :person, presence: true
  validates :person_id, uniqueness: { scope: :questionnaire_id }
end
