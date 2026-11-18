# frozen_string_literal: true

# Every email's buttons are the one standard button (EmailButton), whatever
# the view or the stored template drew: the HTML is passed through
# EmailButton.standardize as it goes out, and in the development previews.
class EmailButtonInterceptor
  def self.delivering_email(message)
    html_parts(message).each do |part|
      was = part.body.decoded.to_s.dup.force_encoding("UTF-8")
      now = EmailButton.standardize(was)
      part.body = now unless now == was
    end
  rescue StandardError => e
    # Never stop an email over the look of its button.
    Rails.logger.warn("[EmailButtonInterceptor] #{e.class}: #{e.message}")
  end

  def self.previewing_email(message) = delivering_email(message)

  def self.html_parts(part)
    return part.parts.flat_map { |child| html_parts(child) } if part.multipart?

    part.mime_type == "text/html" && !part.attachment? ? [ part ] : []
  end
end
