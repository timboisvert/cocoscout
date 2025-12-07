# frozen_string_literal: true

# Mailgun configuration
# https://github.com/mailgun/mailgun-ruby

if defined?(Mailgun)
  Mailgun.configure do |config|
    config.api_key = ENV["MAILGUN_API_KEY"]
  end
end
