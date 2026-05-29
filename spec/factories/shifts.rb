# frozen_string_literal: true

FactoryBot.define do
  factory :shift do
    association :organization
    association :house_role
    starts_at { 1.week.from_now.change(hour: 18) }
    ends_at { 1.week.from_now.change(hour: 22) }
    required_count { 1 }
    coverage_mode { :needs_assignment }

    trait :covered_by_renter do
      coverage_mode { :covered_by_renter }
      renter_name { "Acme Corp" }
    end

    trait :not_needed do
      coverage_mode { :not_needed }
    end

    # A daytime shift (starts before the 5pm evening cutoff).
    trait :afternoon do
      starts_at { 1.week.from_now.change(hour: 13) }
      ends_at { 1.week.from_now.change(hour: 16) }
    end
  end
end
