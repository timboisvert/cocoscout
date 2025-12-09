# frozen_string_literal: true

# Register the email log interceptor (only once)
# Using after_initialize instead of to_prepare to avoid multiple registrations on code reload
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(EmailLogInterceptor)
end
