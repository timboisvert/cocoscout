# frozen_string_literal: true

FactoryBot.define do
  factory :org_payout do
    association :organization
    association :course_offering
    amount_cents { 4750 }
    payment_method { "zelle" }
    status { "paid" }
    paid_at { Time.current }
    payout_type { "full_course" }
    notes { "Test payment" }

    trait :pending do
      status { "pending" }
      paid_at { nil }
    end

    trait :custom do
      payout_type { "custom" }
    end

    trait :per_session do
      payout_type { "per_session" }
      covers_sessions { [ 1, 2 ] }
    end
  end
end
