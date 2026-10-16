# frozen_string_literal: true

# What someone answers on a sign-up form's questions, kept with their
# registration so producers see it on the roster and the printed list
# (after-V1 #1). The page posts answers the way audition submissions do:
# question[ID] carries the value (a hash for checkboxes, JSON for a ranking)
# and file_upload[ID] the file.
#
#   answers = SignUpAnswers.read(questions, params)
#   answers.problem  # => "Please answer: What will you perform?" (register nobody), or nil
#   answers.save!(registration)
module SignUpAnswers
  Result = Struct.new(:answers, :missing, :file_errors) do
    # Why the sign-up can't go through yet, as one line for the page's flash.
    def problem
      return "Please answer: #{missing.map(&:text).to_sentence}" if missing.any?
      file_errors.first
    end

    def save!(registration)
      answers.each do |answer|
        answer.sign_up_registration = registration
        answer.save!
      end
    end
  end

  module_function

  def questions_for(form)
    form.questions.includes(:question_options).order(:position)
  end

  # Unsaved answers for the questions asked, the required ones left blank, and
  # what's wrong with any file (type or size), checked before anyone is
  # registered: a registration's jobs enqueue straight away, so it can't be
  # rolled back once made.
  def read(questions, params)
    values = params[:question] || {}
    files = params[:file_upload] || {}
    answers = []
    missing = []

    questions.each do |question|
      answer =
        if question.question_type == "file_upload"
          file = files[question.id.to_s]
          if file.respond_to?(:original_filename)
            Answer.new(question: question, value: file.original_filename).tap { |a| a.file.attach(file) }
          end
        else
          value = stored_value(values[question.id.to_s])
          Answer.new(question: question, value: value) if value
        end

      if answer
        answers << answer
      elsif question.required
        missing << question
      end
    end

    file_errors = answers.select { |a| a.file.attached? }.flat_map do |answer|
      answer.validate
      answer.errors.full_messages_for(:file).map { |message| "#{answer.question.text}: #{message}" }
    end

    Result.new(answers, missing, file_errors)
  end

  # The value as answers store it, or nil when nothing was given: a checkbox
  # question's ticked boxes as a JSON object (Answer#value_as_array reads its
  # keys), everything else as posted.
  def stored_value(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    if raw.is_a?(Hash)
      ticked = raw.to_h.select { |_, v| v.present? }
      ticked.any? ? ticked.to_json : nil
    else
      raw.presence
    end
  end
end
