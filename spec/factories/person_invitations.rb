# frozen_string_literal: true

FactoryBot.define do
  factory :person_invitation do
    sequence(:email) { |n| "person#{n}@example.com" }
    association :organization
    token { SecureRandom.hex(20) }
  end
end
