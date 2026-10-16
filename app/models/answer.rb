# frozen_string_literal: true

class Answer < ApplicationRecord
  include QuestionFileUpload

  belongs_to :question
  # An answer comes with an audition request or a sign-up registration,
  # exactly one of the two (the answers_one_owner check holds it in the DB).
  belongs_to :audition_request, optional: true
  belongs_to :sign_up_registration, optional: true

  validates :question, presence: true
  validate :one_owner

  def value_as_array
    return [ value ] unless question.present?

    type_class = question.question_type_class
    return [ value ] unless type_class

    type_class.parse_answer_value(value)
  end

  private

  def one_owner
    owners = [ audition_request, sign_up_registration ].compact
    errors.add(:base, "must belong to an audition request or a sign-up registration") unless owners.size == 1
  end
end
