# frozen_string_literal: true

module QuestionTypes
  class FileUploadType < Base
    def self.key
      "file_upload"
    end

    def self.label
      "File Upload"
    end

    def self.sort_order
      7
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
QuestionTypes::Base.register("file_upload", QuestionTypes::FileUploadType)
