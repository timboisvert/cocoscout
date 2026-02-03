# frozen_string_literal: true

FactoryBot.define do
  factory :production do
    association :organization
    sequence(:name) { |n| "Production #{n}" }
    contact_email { 'contact@example.com' }
  end

  factory :production_permission do
    association :user
    association :production
    role { "manager" }

    trait :viewer do
      role { "viewer" }
    end
  end
end
