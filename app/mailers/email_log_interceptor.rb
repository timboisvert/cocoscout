# frozen_string_literal: true

# Interceptor to log all outgoing emails
class EmailLogInterceptor
  def self.delivering_email(message)
    # Extract user from message headers
    user_id = message.header["X-User-ID"]&.value

    unless user_id
      Rails.logger.warn("Email sent without user tracking: #{message.subject}")
      return
    end

    user = User.find_by(id: user_id)
    unless user
      Rails.logger.warn("Email sent with invalid user_id: #{user_id}")
      return
    end

    # Extract recipient entity if provided
    recipient_entity = nil
    recipient_entity_type = message.header["X-Recipient-Entity-Type"]&.value
    recipient_entity_id = message.header["X-Recipient-Entity-ID"]&.value
    if recipient_entity_type.present? && recipient_entity_id.present?
      recipient_entity = recipient_entity_type.constantize.find_by(id: recipient_entity_id)
    end

    # Extract email batch if provided
    email_batch_id = message.header["X-Email-Batch-ID"]&.value
    email_batch = EmailBatch.find_by(id: email_batch_id) if email_batch_id.present?

    # Extract organization if provided
    organization_id = message.header["X-Organization-ID"]&.value
    organization = Organization.find_by(id: organization_id) if organization_id.present?

    # Create the email log
    email_log = EmailLog.create!(
      user: user,
      recipient: Array(message.to).join(", "),
      subject: message.subject,
      mailer_class: message.header["X-Mailer-Class"]&.value,
      mailer_action: message.header["X-Mailer-Action"]&.value,
      message_id: message.message_id,
      sent_at: Time.current,
      delivery_status: "queued",
      recipient_entity: recipient_entity,
      email_batch: email_batch,
      organization: organization
    )

    # Attach body as Active Storage file (stored in S3 in production)
    body_html = extract_body_with_inline_images(message)
    if body_html.present?
      email_log.body_file.attach(
        io: StringIO.new(body_html),
        filename: "email_#{email_log.id}.html",
        content_type: "text/html"
      )
    end
  rescue StandardError => e
    # Log the error but don't prevent email delivery
    Rails.logger.error("Failed to log email: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end

  def self.extract_body_with_inline_images(message)
    html_body = extract_body(message)
    return html_body unless html_body.present?

    # Find all inline attachments and convert CID references to data URLs
    if message.attachments.any?
      message.attachments.each do |attachment|
        next unless attachment.inline?

        # Get the Content-ID (without < >)
        cid = attachment.cid
        next unless cid

        # Convert attachment to base64 data URL
        content_type = attachment.content_type
        base64_data = Base64.strict_encode64(attachment.body.decoded)
        data_url = "data:#{content_type};base64,#{base64_data}"

        # Replace cid: references with data URLs
        html_body = html_body.gsub(/cid:#{Regexp.escape(cid)}/, data_url)
      end
    end

    html_body
  end

  def self.extract_body(message)
    # Prefer HTML over text for better rendering
    html = find_html_part(message)
    return html if html.present?

    # Fallback to text if no HTML
    text = find_text_part(message)
    return text if text.present?

    # Last resort: decode the message directly
    message.decoded
  end

  def self.find_html_part(part)
    if part.multipart?
      # Recursively search for HTML part in multipart messages
      part.parts.each do |subpart|
        html = find_html_part(subpart)
        return html if html.present?
      end
      nil
    elsif part.content_type&.include?("text/html")
      part.decoded
    end
  end

  def self.find_text_part(part)
    if part.multipart?
      # Recursively search for text part in multipart messages
      part.parts.each do |subpart|
        text = find_text_part(subpart)
        return text if text.present?
      end
      nil
    elsif part.content_type&.include?("text/plain")
      part.decoded
    end
  end
end
