# frozen_string_literal: true

FactoryBot.define do
  factory :contractor do
    organization
    sequence(:name) { |n| "Contractor #{n}" }
    email { "contact@#{name.parameterize}.com" }
    phone { "(555) 123-4567" }
    address { "123 Main Street\nCity, State 12345" }

    trait :with_contracts do
      transient do
        contracts_count { 2 }
      end

      after(:create) do |contractor, evaluator|
        create_list(:contract, evaluator.contracts_count, contractor: contractor, organization: contractor.organization)
      end
    end
  end
end
