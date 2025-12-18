# frozen_string_literal: true

class ShowLink < ApplicationRecord
  belongs_to :show
  validates :url, presence: true
  validate :url_must_be_safe

  # Returns the URL only if it's safe (http/https), nil otherwise
  def safe_url
    return nil if url.blank?

    uri = URI.parse(url)
    %w[http https].include?(uri.scheme) ? url : nil
  rescue URI::InvalidURIError
    nil
  end

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

  private

  def url_must_be_safe
    return if url.blank?

    begin
      uri = URI.parse(url)
      unless %w[http https].include?(uri.scheme)
        errors.add(:url, "must be a valid http or https URL")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "is not a valid URL")
    end
  end
end
