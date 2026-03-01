# frozen_string_literal: true

# Validates that external_url is a safe HTTP/HTTPS URL.
# Prevents javascript: and other potentially dangerous URL schemes.
module SafeExternalUrl
  extend ActiveSupport::Concern

  ALLOWED_SCHEMES = %w[http https].freeze

  included do
    validate :external_url_is_safe, if: -> { external_url.present? }
  end

  # Returns the external_url only if it's safe, nil otherwise
  def safe_external_url
    return nil if external_url.blank?

    uri = URI.parse(external_url)
    ALLOWED_SCHEMES.include?(uri.scheme&.downcase) ? external_url : nil
  rescue URI::InvalidURIError
    nil
  end

  private

  def external_url_is_safe
    return if external_url.blank?

    begin
      uri = URI.parse(external_url)
      unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
        errors.add(:external_url, "must be an HTTP or HTTPS URL")
      end
    rescue URI::InvalidURIError
      errors.add(:external_url, "is not a valid URL")
    end
  end
end
