# frozen_string_literal: true

FactoryBot.define do
  factory :person_advance do
    association :person
    association :production
    association :issued_by, factory: :user
    original_amount { 100.0 }
    remaining_balance { 100.0 }
    status { "pending" }
    advance_type { "general" }
    issued_at { Time.current }
    notes { "Test advance" }

    trait :paid do
      paid_at { Time.current }
      association :paid_by, factory: :user
      payment_method { "venmo" }
    end

    trait :partial do
      status { "partial" }
      remaining_balance { 50.0 }
    end

    trait :settled do
      status { "settled" }
      remaining_balance { 0.0 }
    end

    trait :written_off do
      status { "written_off" }
    end

    trait :show_specific do
      advance_type { "show" }
      association :show
    end
  end

  factory :advance_recovery do
    association :person_advance
    association :show_payout_line_item
    amount { 25.0 }
    recovered_at { Time.current }
  end
end
