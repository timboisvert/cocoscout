# frozen_string_literal: true

FactoryBot.define do
  factory :payroll_run do
    association :organization
    association :created_by, factory: :user
    period_start { 2.weeks.ago.beginning_of_week }
    period_end { 1.week.ago.end_of_week }
    status { "pending" }

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
      association :processed_by, factory: :user
      processed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :with_schedule do
      association :payroll_schedule
    end
  end

  factory :payroll_line_item do
    association :payroll_run
    association :person
    gross_amount { 150.0 }
    net_amount { 150.0 }
    advance_deductions { 0.0 }
    show_count { 3 }

    trait :paid do
      manually_paid { true }
      paid_at { Time.current }
    end
  end

  factory :payroll_schedule do
    association :organization
    sequence(:name) { |n| "Schedule #{n}" }
    frequency { "weekly" }
    day_of_week { 5 } # Friday
    active { true }

    trait :bi_weekly do
      frequency { "bi_weekly" }
    end

    trait :monthly do
      frequency { "monthly" }
      day_of_month { 15 }
    end

    trait :inactive do
      active { false }
    end
  end
end
