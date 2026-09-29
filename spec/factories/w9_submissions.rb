# frozen_string_literal: true

FactoryBot.define do
  factory :w9_submission do
    association :organization
    association :person
    legal_name { "Sam Staffer" }
    tax_classification { "individual" }
    address_line1 { "123 Main St" }
    city { "Springfield" }
    state { "IL" }
    zip { "62701" }
    tin_type { "ssn" }
    tin { "123-45-6789" }
    signature_name { "Sam Staffer" }
    signed_at { Time.current }
  end
end
