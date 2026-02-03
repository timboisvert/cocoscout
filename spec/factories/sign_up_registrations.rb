# frozen_string_literal: true

FactoryBot.define do
  factory :sign_up_registration do
    sign_up_slot
    person
    sequence(:position) { |n| n }
    status { "confirmed" }
    registered_at { Time.current }

    trait :waitlisted do
      status { "waitlisted" }
    end

    trait :queued do
      status { "queued" }
      sign_up_slot { nil }
      sign_up_form_instance
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :guest do
      person { nil }
      guest_name { "Guest User" }
      guest_email { "guest@example.com" }
    end
  end
end
