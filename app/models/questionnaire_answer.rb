# frozen_string_literal: true

class QuestionnaireAnswer < ApplicationRecord
  include QuestionFileUpload

  belongs_to :questionnaire_response
  belongs_to :question

  validates :question, presence: true

  # URL type detection for url question answers
  def youtube_url?
    value.present? && value.match?(%r{\A\s*https?://(www\.)?(youtube\.com/watch\?v=|youtu\.be/)}i)
  end

  def spotify_url?
    value.present? && value.match?(%r{\A\s*https?://open\.spotify\.com/}i)
  end

  def youtube_embed_id
    return unless youtube_url?

    match = value.match(%r{(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]+)})
    match[1] if match
  end

  def spotify_embed_uri
    return unless spotify_url?

    # Convert https://open.spotify.com/track/123 to spotify:track:123
    match = value.match(%r{open\.spotify\.com/(track|album|playlist|artist)/([a-zA-Z0-9]+)})
    "spotify:#{match[1]}:#{match[2]}" if match
  end

  # Custom serializer to handle both old string values and new JSON values
  class ValueSerializer
    def self.dump(value)
      return nil if value.nil?

      # For plain strings (text answers), keep as-is
      # For hashes/arrays, convert to JSON
      if value.is_a?(Hash) || value.is_a?(Array)
        JSON.generate(value)
      else
        value.to_s
      end
    end

    def self.load(value)
      return nil if value.nil?
      return value unless value.is_a?(String)

      # Check if it starts with { or [ which indicates JSON
      if value.strip.start_with?("{", "[")
        begin
          JSON.parse(value)
        rescue JSON::ParserError
          # Not valid JSON, might be old Ruby hash format like {"key"=>"value"}
          # Try to convert Ruby hash format to JSON format
          begin
            # Replace => with : for JSON parsing
            json_string = value.gsub(/=>/, ":")
            JSON.parse(json_string)
          rescue JSON::ParserError
            # Still fails, return as-is
            value
          end
        end
      else
        # Plain string, return as-is
        value
      end
    end
  end

  serialize :value, coder: ValueSerializer

  def value_as_array
    return [ value ] unless question.present?

    type_class = question.question_type_class
    return [ value ] unless type_class

    type_class.parse_answer_value(value)
  end
end
