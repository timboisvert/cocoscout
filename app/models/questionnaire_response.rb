class QuestionnaireResponse < ApplicationRecord
  belongs_to :questionnaire
  belongs_to :respondent, polymorphic: true
  has_many :questionnaire_answers, dependent: :destroy

  validates :questionnaire, presence: true
  validates :respondent, presence: true
  validates :respondent_id, uniqueness: { scope: [:questionnaire_id, :respondent_type] }
end
