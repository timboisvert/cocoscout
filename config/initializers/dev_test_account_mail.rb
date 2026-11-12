# frozen_string_literal: true

# Development only. letter_opener opens every email in the browser, and the
# morning jobs (today's shows, yesterday's ticket sales) write to every
# manager, including the localhost test accounts at @cocoscout.test: Tim woke
# up to a row of tabs addressed to dev-manager@cocoscout.test each day (Tim,
# 2026-11-11). An email written only to those accounts is not delivered, so
# nothing opens. One that also goes to a real dev login still opens.
if Rails.env.development?
  class DevTestAccountMailInterceptor
    TEST_DOMAIN = "@cocoscout.test"

    def self.delivering_email(message)
      recipients = Array(message.to) + Array(message.cc) + Array(message.bcc)
      message.perform_deliveries = false if recipients.any? && recipients.all? { |address| address.to_s.downcase.end_with?(TEST_DOMAIN) }
    end
  end

  Rails.application.config.after_initialize do
    ActionMailer::Base.register_interceptor(DevTestAccountMailInterceptor)
  end
end
