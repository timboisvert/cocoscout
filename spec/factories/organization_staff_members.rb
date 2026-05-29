# frozen_string_literal: true

FactoryBot.define do
  factory :organization_staff_member do
    association :organization
    association :person

    trait :archived do
      archived_at { 1.day.ago }
    end
  end
end
