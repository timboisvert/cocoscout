# frozen_string_literal: true

FactoryBot.define do
  factory :session do
    user
    user_agent { "RSpec Test Agent" }
    ip_address { "127.0.0.1" }
  end
end
