# frozen_string_literal: true

# Register the email log interceptor
Rails.application.config.to_prepare do
  ActionMailer::Base.register_interceptor(EmailLogInterceptor)
end
