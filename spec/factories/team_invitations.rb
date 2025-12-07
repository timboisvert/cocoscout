# frozen_string_literal: true

FactoryBot.define do
  factory :team_invitation do
    sequence(:email) { |n| "invitee#{n}@example.com" }
    association :organization
    token { SecureRandom.hex(10) }
  end
end
