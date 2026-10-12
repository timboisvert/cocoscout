# frozen_string_literal: true

# Every email goes out with a plain-text version beside its HTML (Tim,
# 2026-10-12: most of ours were HTML only, which spam filters mark down).
# Mailers that write their own text part keep it; for the rest, the text is
# made from the HTML at delivery, so no mailer has to remember. The HTML part
# is swapped for a multipart/alternative holding the text then the HTML, in
# place, so inline images (the logo, ticket QR codes) and attachments (PDFs)
# stay where they were.
class PlainTextAlternativeInterceptor
  def self.delivering_email(message)
    return if text_part(message)

    if message.multipart?
      parent, html = parent_of_html(message)
      return unless html

      index = parent.parts.index(html)
      parent.parts[index] = alternative(html)
    elsif message.mime_type == "text/html"
      html = message.body.decoded
      message.body = nil
      message.content_type = "multipart/alternative"
      message.add_part(text_part_for(html))
      message.add_part(Mail::Part.new(content_type: "text/html; charset=UTF-8", body: html))
    end
  rescue StandardError => e
    # Never stop an email over its text part.
    Rails.logger.warn("[PlainTextAlternativeInterceptor] #{e.class}: #{e.message}")
  end

  def self.text_part(part)
    return part if !part.multipart? && part.mime_type == "text/plain" && !part.attachment?

    part.parts.each do |child|
      found = text_part(child)
      return found if found
    end
    nil
  end

  # [the container holding the HTML part, the HTML part], depth first.
  def self.parent_of_html(container)
    container.parts.each do |child|
      return [ container, child ] if !child.multipart? && child.mime_type == "text/html" && !child.attachment?
      next unless child.multipart?

      found = parent_of_html(child)
      return found if found.last
    end
    [ nil, nil ]
  end

  def self.alternative(html_part)
    wrapper = Mail::Part.new(content_type: "multipart/alternative")
    wrapper.add_part(text_part_for(html_part.decoded))
    wrapper.add_part(html_part)
    wrapper
  end

  def self.text_part_for(html)
    Mail::Part.new(content_type: "text/plain; charset=UTF-8", body: EmailPlainText.from_html(html))
  end

  private_class_method :text_part, :parent_of_html, :alternative, :text_part_for
end
