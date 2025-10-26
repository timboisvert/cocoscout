FactoryBot.define do
  factory :location do
    association :production_company
    sequence(:name) { |n| "Location #{n}" }
    address1 { "123 Main Street" }
    address2 { "Suite 100" }
    city { "New York" }
    state { "NY" }
    postal_code { "10001" }
    default { false }

    trait :default do
      default { true }
    end
  end
end
