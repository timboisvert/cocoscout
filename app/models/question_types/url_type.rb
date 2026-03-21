# frozen_string_literal: true

module QuestionTypes
  class UrlType < Base
    def self.key
      "url"
    end

    def self.label
      "URL / Link"
    end

    def self.sort_order
      8
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
QuestionTypes::Base.register("url", QuestionTypes::UrlType)
