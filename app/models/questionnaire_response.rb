# frozen_string_literal: true

class QuestionnaireResponse < ApplicationRecord
  belongs_to :questionnaire
  belongs_to :respondent, polymorphic: true
  has_many :questionnaire_answers, dependent: :destroy

  validates :questionnaire, presence: true
  validates :respondent, presence: true
  validates :respondent_id, uniqueness: { scope: %i[questionnaire_id respondent_type] }

  # Helper method for backward compatibility
  def person
    respondent if respondent_type == "Person"
  end
end
