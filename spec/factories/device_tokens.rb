# frozen_string_literal: true

FactoryBot.define do
  factory :device_token do
    user
    sequence(:token) { |n| "device_token_#{n}" }
    platform { "ios" }
  end
end
