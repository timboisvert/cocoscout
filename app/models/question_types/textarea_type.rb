# frozen_string_literal: true

module QuestionTypes
  class TextareaType < Base
    def self.key
      "textarea"
    end

    def self.label
      "Long Text"
    end

    def self.sort_order
      2
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
QuestionTypes::Base.register("textarea", QuestionTypes::TextareaType)
