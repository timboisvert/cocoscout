class QuestionnaireResponse < ApplicationRecord
  belongs_to :questionnaire
  belongs_to :person
  has_many :questionnaire_answers, dependent: :destroy

  validates :questionnaire, presence: true
  validates :person, presence: true
  validates :person_id, uniqueness: { scope: :questionnaire_id }
end
