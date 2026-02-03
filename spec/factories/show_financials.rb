# frozen_string_literal: true

FactoryBot.define do
  factory :show_financials do
    association :show
    revenue_type { "ticket_sales" }
    ticket_count { 100 }
    ticket_revenue { 1500.0 }
    expenses { 200.0 }
    data_confirmed { false }

    trait :complete do
      data_confirmed { true }
    end

    trait :flat_fee do
      revenue_type { "flat_fee" }
      ticket_count { nil }
      ticket_revenue { nil }
      flat_fee { 2000.0 }
    end

    trait :with_other_revenue do
      other_revenue { 250.0 }
    end

    trait :with_expense_details do
      expense_details do
        [
          { "description" => "Stage manager", "amount" => 100.0 },
          { "description" => "Props", "amount" => 50.0 }
        ]
      end
    end
  end

  factory :show_payout do
    association :show
    status { "awaiting_payout" }
    total_payout { 0.0 }

    trait :paid do
      status { "paid" }
    end

    trait :with_scheme do
      association :payout_scheme
    end

    trait :with_overrides do
      override_rules do
        {
          "distribution" => { "method" => "equal" }
        }
      end
    end
  end

  factory :show_payout_line_item do
    association :show_payout
    association :payee, factory: :person
    amount { 50.0 }
    is_guest { false }
    manually_paid { false }
    paid_independently { false }
    advance_deduction { 0.0 }

    trait :paid do
      manually_paid { true }
      paid_at { Time.current }
    end

    trait :guest do
      payee { nil }
      guest_name { "Guest Performer" }
      is_guest { true }
    end
  end

  factory :payout_scheme do
    association :production
    sequence(:name) { |n| "Payout Scheme #{n}" }
    rules do
      {
        "distribution" => {
          "method" => "equal"
        }
      }
    end
    is_default { false }

    trait :default do
      is_default { true }
    end

    trait :per_ticket do
      rules do
        {
          "distribution" => {
            "method" => "per_ticket",
            "per_ticket_rate" => 0.50
          }
        }
      end
    end

    trait :flat_fee do
      rules do
        {
          "distribution" => {
            "method" => "flat_fee",
            "flat_amount" => 25.0
          }
        }
      end
    end
  end
end
