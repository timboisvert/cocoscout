# frozen_string_literal: true

FactoryBot.define do
  factory :seating_configuration do
    organization
    sequence(:name) { |n| "Seating Configuration #{n}" }
    status { :active }

    trait :with_zones do
      after(:create) do |config|
        create(:seating_zone, seating_configuration: config, name: "Front Row", zone_type: "individual_seats", unit_count: 11, capacity_per_unit: 1, position: 0)
        create(:seating_zone, seating_configuration: config, name: "Back Rows", zone_type: "rows", unit_count: 5, capacity_per_unit: 11, position: 1)
      end
    end

    trait :with_tiers do
      after(:create) do |config|
        create(:ticket_tier, seating_configuration: config, name: "General Admission", capacity: 50, position: 0)
        create(:ticket_tier, seating_configuration: config, name: "VIP", capacity: 10, position: 1)
      end
    end
  end

  factory :seating_zone do
    seating_configuration
    sequence(:name) { |n| "Zone #{n}" }
    zone_type { "individual_seats" }
    unit_count { 10 }
    capacity_per_unit { 1 }
    sequence(:position) { |n| n }
  end

  factory :ticket_tier do
    seating_configuration
    sequence(:name) { |n| "Tier #{n}" }
    capacity { 50 }
    default_price_cents { 2000 }
    sequence(:position) { |n| n }
  end
end
