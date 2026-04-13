# frozen_string_literal: true

FactoryBot.define do
  factory :contract do
    association :organization
    contractor { nil }
    contractor_name { "Venue Corp" }
    contractor_email { "venue@example.com" }
    status { :draft }
    contract_start_date { 1.month.from_now }
    contract_end_date { 3.months.from_now }
    draft_data { {} }

    trait :with_contractor do
      contractor { association :contractor, organization: organization }
      contractor_name { contractor.name }
      contractor_email { contractor.email }
    end

    trait :active do
      status { :active }
      activated_at { Time.current }
    end

    trait :completed do
      status { :completed }
      activated_at { 1.month.ago }
      completed_at { Time.current }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { Time.current }
    end

    trait :with_bookings do
      draft_data do
        {
          "bookings" => [
            {
              "date" => 1.month.from_now.to_date.to_s,
              "start_time" => "19:00",
              "end_time" => "22:00",
              "event_type" => "show"
            }
          ]
        }
      end
    end

    trait :with_payment_schedule do
      draft_data do
        {
          "payment_config" => {
            "type" => "flat",
            "amount" => 500.0
          }
        }
      end
    end

    trait :revenue_share do
      draft_data do
        {
          "payment_structure" => "revenue_share",
          "payment_config" => {
            "revenue_our_share" => 70,
            "revenue_their_share" => 30,
            "revenue_settlement" => "monthly"
          }
        }
      end
    end

    trait :revenue_share_weekly do
      draft_data do
        {
          "payment_structure" => "revenue_share",
          "payment_config" => {
            "revenue_our_share" => 60,
            "revenue_their_share" => 40,
            "revenue_settlement" => "weekly"
          }
        }
      end
    end

    trait :revenue_share_per_event do
      draft_data do
        {
          "payment_structure" => "revenue_share",
          "payment_config" => {
            "revenue_our_share" => 80,
            "revenue_their_share" => 20,
            "revenue_settlement" => "per_event"
          }
        }
      end
    end
  end

  factory :contract_document do
    association :contract
    sequence(:name) { |n| "Document #{n}" }
    document_type { "contract" }

    trait :signed do
      signed_at { Time.current }
      signed_by { "John Doe" }
    end
  end

  factory :contract_payment do
    association :contract
    amount { 500.0 }
    due_date { 1.month.from_now }
    status { "pending" }
    direction { "incoming" }
    description { "Payment" }

    trait :paid do
      status { "paid" }
      paid_date { Date.current }
    end

    trait :overdue do
      due_date { 1.week.ago }
    end

    trait :outgoing do
      direction { "outgoing" }
    end

    trait :revenue_share_tbd do
      amount { 0 }
      amount_tbd { true }
      description { "Revenue Share Settlement" }
    end
  end

  factory :space_rental do
    association :contract
    association :location
    starts_at { 1.month.from_now.change(hour: 18) }
    ends_at { 1.month.from_now.change(hour: 23) }
    confirmed { false }
  end
end
