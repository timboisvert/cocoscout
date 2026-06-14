# frozen_string_literal: true

FactoryBot.define do
  factory :staffing_finalization do
    association :organization
    week_start { Date.current.beginning_of_week }
    finalized_at { Time.current }
  end
end
