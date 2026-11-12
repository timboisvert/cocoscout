# frozen_string_literal: true

# Register the email log interceptor (only once)
# Using after_initialize instead of to_prepare to avoid multiple registrations on code reload
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(EmailLogInterceptor)
  # Every email's buttons are the one standard button (EmailButton), in the
  # development previews too.
  ActionMailer::Base.register_interceptor(EmailButtonInterceptor)
  ActionMailer::Base.register_preview_interceptor(EmailButtonInterceptor)
  # A plain-text version beside every HTML email (PlainTextAlternativeInterceptor).
  ActionMailer::Base.register_interceptor(PlainTextAlternativeInterceptor)
end
