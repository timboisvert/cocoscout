# frozen_string_literal: true

FactoryBot.define do
  factory :sign_up_form do
    production
    name { "Test Sign-Up Form" }
    scope { "single_event" }
    active { true }
    slot_generation_mode { "numbered" }
    slot_count { 10 }
    slot_capacity { 1 }

    trait :with_show do
      association :show
    end

    trait :repeated do
      scope { "repeated" }
      event_matching { "all" }
    end

    trait :shared_pool do
      scope { "shared_pool" }
    end

    trait :inactive do
      active { false }
    end

    trait :with_short_code do
      short_code { SecureRandom.alphanumeric(6).upcase }
    end
  end
end
