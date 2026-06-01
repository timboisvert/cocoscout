# frozen_string_literal: true

FactoryBot.define do
  factory :venue do
    sequence(:name) { |n| "Venue #{n}" }
    address1 { "100 Main St" }
    city { "Chicago" }
    state { "IL" }
    postal_code { "60647" }
    country { "US" }
    venue_type { :bar }
    timezone { "America/Chicago" }

    trait :geocoded do
      lat { 41.8781 }
      lng { -87.6298 }
      geocoded_at { Time.current }
    end
  end
end
