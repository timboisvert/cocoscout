# frozen_string_literal: true

module QuestionTypes
  class MultipleSingleType < Base
    def self.key
      "multiple-single"
    end

    def self.label
      "Select Single Option"
    end

    def self.needs_options?
      true
    end

    def self.parse_answer_value(value)
      begin
        parsed_value = JSON.parse(value.gsub("=>", ":"))
        parsed_value.keys
      rescue JSON::ParserError
        [] # If parsing fails, return an empty array
      end
    end
  end
end

# Register the type
QuestionTypes::Base.register("multiple-single", QuestionTypes::MultipleSingleType)
