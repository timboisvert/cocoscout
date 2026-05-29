# frozen_string_literal: true

FactoryBot.define do
  factory :staff_unavailability do
    association :person
    date { Date.current + 1.week }
    scope { :all_day }

    trait :afternoon do
      scope { :day_shifts }
    end

    trait :evening do
      scope { :evening_shifts }
    end
  end
end
