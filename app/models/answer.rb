# frozen_string_literal: true

class Answer < ApplicationRecord
  belongs_to :question
  belongs_to :audition_request

  validates :question, presence: true

  def value_as_array
    return [ value ] unless question.present?

    type_class = question.question_type_class
    return [ value ] unless type_class

    type_class.parse_answer_value(value)
  end
end
