# frozen_string_literal: true

namespace :question_types do
  desc "Verify all Question records have valid question types"
  task verify: :environment do
    puts "Verifying question types..."
    puts "=" * 80

    all_questions = Question.all
    total_count = all_questions.count
    valid_count = 0
    invalid_questions = []

    puts "Total questions found: #{total_count}"
    puts

    if total_count.zero?
      puts "No questions found in database."
      exit 0
    end

    all_questions.find_each do |question|
      type_class = question.question_type_class

      if type_class.nil?
        invalid_questions << {
          id: question.id,
          text: question.text.truncate(50),
          question_type: question.question_type,
          error: "Unknown question type"
        }
      elsif type_class.needs_options? && question.question_options.empty?
        invalid_questions << {
          id: question.id,
          text: question.text.truncate(50),
          question_type: question.question_type,
          error: "Missing required question_options"
        }
      else
        valid_count += 1
      end
    end

    puts "Valid questions: #{valid_count}/#{total_count}"
    puts

    if invalid_questions.any?
      puts "INVALID QUESTIONS FOUND:"
      puts "-" * 80
      invalid_questions.each do |q|
        puts "ID: #{q[:id]}"
        puts "  Text: #{q[:text]}"
        puts "  Type: #{q[:question_type]}"
        puts "  Error: #{q[:error]}"
        puts
      end
      puts "=" * 80
      puts "❌ Verification FAILED: #{invalid_questions.count} invalid question(s) found"
      exit 1
    else
      puts "=" * 80
      puts "✅ Verification PASSED: All questions have valid types"
      exit 0
    end
  end

  desc "List all registered question types"
  task list_types: :environment do
    puts "Registered Question Types:"
    puts "=" * 80

    QuestionTypes::Base.all_types.each do |type_class|
      puts
      puts "Key:           #{type_class.key}"
      puts "Label:         #{type_class.label}"
      puts "Needs Options: #{type_class.needs_options? ? 'Yes' : 'No'}"

      count = Question.where(question_type: type_class.key).count
      puts "Usage Count:   #{count}"
    end

    puts
    puts "=" * 80
  end

  desc "Show question type statistics"
  task stats: :environment do
    puts "Question Type Statistics:"
    puts "=" * 80

    total = Question.count
    puts "Total Questions: #{total}"
    puts

    if total.zero?
      puts "No questions found in database."
      exit 0
    end

    type_counts = Question.group(:question_type).count
    type_counts.each do |type, count|
      percentage = (count.to_f / total * 100).round(1)
      type_class = QuestionTypes::Base.find(type)
      label = type_class ? type_class.label : "Unknown (#{type})"

      puts "#{label.ljust(30)} #{count.to_s.rjust(5)} (#{percentage}%)"
    end

    puts
    puts "=" * 80
  end
end
