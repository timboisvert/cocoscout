# frozen_string_literal: true

module QuestionTypes
  class RankingType < Base
    def self.key
      "ranking"
    end

    def self.label
      "Ranking"
    end

    def self.sort_order
      6
    end

    def self.needs_options?
      true
    end

    def self.parse_answer_value(value)
      # Value is stored as JSON array of option texts in ranked order
      # e.g., '["Option A", "Option B", "Option C"]'

      parsed_value = JSON.parse(value)
      parsed_value.is_a?(Array) ? parsed_value : []
    rescue JSON::ParserError
      []
    end
  end
end

# Register the type
QuestionTypes::Base.register("ranking", QuestionTypes::RankingType)
