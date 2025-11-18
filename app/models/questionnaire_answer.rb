class QuestionnaireAnswer < ApplicationRecord
  belongs_to :questionnaire_response
  belongs_to :question

  validates :question, presence: true

  def value_as_array
    return [ value ] unless question.present?

    type_class = question.question_type_class
    return [ value ] unless type_class

    type_class.parse_answer_value(value)
  end
end
