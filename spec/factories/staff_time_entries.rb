# frozen_string_literal: true

FactoryBot.define do
  factory :staff_time_entry do
    association :organization
    association :person
    started_at { Time.current.change(hour: 18) }
    ended_at { Time.current.change(hour: 23) }
    source { "manual" }

    trait :from_shift do
      source { "shift" }
      association :shift_assignment
    end

    trait :paid do
      association :payout_batch
      paid_at { Time.current }
    end
  end
end
