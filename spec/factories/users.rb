# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { 'password123' }
    welcomed_at { 1.day.ago }
  end
end
