# frozen_string_literal: true

module QuestionTypes
  class MultipleMultipleType < Base
    def self.key
      "multiple-multiple"
    end

    def self.label
      "Select Multiple Options"
    end

    def self.sort_order
      4
    end

    def self.needs_options?
      true
    end

    def self.parse_answer_value(value)
      parsed_value = JSON.parse(value.gsub("=>", ":"))
      parsed_value.keys
    rescue JSON::ParserError
      [] # If parsing fails, return an empty array
    end
  end
end

# Register the type
QuestionTypes::Base.register("multiple-multiple", QuestionTypes::MultipleMultipleType)
