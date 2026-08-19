# frozen_string_literal: true

FactoryBot.define do
  factory :staff_unavailability do
    association :person
    date { Date.current + 1.week }
    scope { :all_day }

    # The two default work time regions (StaffingDayParts::DEFAULT_STAFFING_DAY_PARTS).
    trait :afternoon do
      scope { "afternoon" }
    end

    trait :evening do
      scope { "evening" }
    end
  end
end
