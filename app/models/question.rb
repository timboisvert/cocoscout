# frozen_string_literal: true

class Question < ApplicationRecord
  belongs_to :questionable, polymorphic: true
  has_many :question_options, dependent: :destroy
  has_many :answers, dependent: :destroy
  accepts_nested_attributes_for :question_options, reject_if: :all_blank, allow_destroy: true

  validates :text, presence: true
  validates :question_type, presence: true
  validate :validate_question_options_presence

  def question_type_class
    QuestionTypes::Base.find(question_type)
  end

  private

  def validate_question_options_presence
    return unless question_type.present?

    type_class = question_type_class
    return unless type_class

    return unless type_class.needs_options? && question_options.reject(&:marked_for_destruction?).blank?

    errors.add(:question_options, "must have at least one option for this question type")
  end
end
