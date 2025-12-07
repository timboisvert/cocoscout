# frozen_string_literal: true

class ShowLink < ApplicationRecord
  belongs_to :show
  validates :url, presence: true

  # For backward compatibility, display text if present, otherwise parse from URL
  def display_text
    return text if text.present?

    # Fallback: extract domain from URL for legacy links
    begin
      uri = URI.parse(url)
      uri.host || url
    rescue URI::InvalidURIError
      url
    end
  end
end
