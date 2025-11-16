# frozen_string_literal: true

module QuestionTypes
  class YesnoType < Base
    def self.key
      "yesno"
    end

    def self.label
      "Yes/No"
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
QuestionTypes::Base.register("yesno", QuestionTypes::YesnoType)
