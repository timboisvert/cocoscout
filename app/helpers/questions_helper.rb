# frozen_string_literal: true

module QuestionsHelper
  def render_question_input(question, answers, options = {})
    answer_value = answers.is_a?(Hash) ? answers[question.id.to_s] : answers[question.id]
    missing_required = options[:missing_required_questions]&.include?(question)

    render(
      partial: "shared/questions/input_types/#{question.question_type}",
      locals: {
        question: question,
        answer_value: answer_value,
        missing_required: missing_required,
        required: question.required
      }.merge(options)
    )
  end

  def render_question_answer(answer)
    render(
      partial: "shared/questions/answer_types/#{answer.question.question_type}",
      locals: { answer: answer }
    )
  end
end
