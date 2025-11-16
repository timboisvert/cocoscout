# frozen_string_literal: true

module QuestionTypes
  class TextType < Base
    def self.key
      "text"
    end

    def self.label
      "Short Text"
    end

    def self.needs_options?
      false
    end

    def self.parse_answer_value(value)
      [ value ]
    end
  end
end

# Register the type
QuestionTypes::Base.register("text", QuestionTypes::TextType)
