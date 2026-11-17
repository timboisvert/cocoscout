# frozen_string_literal: true

# Counts every email CocoScout hands to Mailgun, one per recipient
# (MailVolume). A count that fails never stops the email.
class MailVolumeObserver
  def self.delivered_email(message)
    recipients = [ message.to, message.cc, message.bcc ].flatten.compact.size
    MailVolume.count!(recipients)
  rescue StandardError => e
    Rails.logger.error("[MailVolumeObserver] not counted: #{e.class}: #{e.message}")
  end
end
