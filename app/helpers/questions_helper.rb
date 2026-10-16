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

  # An answer as one line of plain text, for a printed list: picks and
  # rankings joined with commas, a file by its name.
  def question_answer_text(answer)
    case answer.question.question_type
    when "file_upload"
      answer.respond_to?(:file) && answer.file.attached? ? answer.file.filename.to_s : answer.value.to_s
    when "yesno"
      answer.value.to_s.capitalize
    when "multiple-multiple", "ranking"
      answer.value_as_array.join(", ")
    else
      answer.value.to_s.squish
    end
  end
end
