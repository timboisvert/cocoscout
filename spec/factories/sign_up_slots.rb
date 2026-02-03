# frozen_string_literal: true

FactoryBot.define do
  factory :sign_up_slot do
    sign_up_form
    sequence(:position) { |n| n }
    capacity { 1 }
    is_held { false }

    trait :held do
      is_held { true }
    end

    trait :with_name do
      name { "Named Slot" }
    end

    trait :high_capacity do
      capacity { 10 }
    end
  end
end
