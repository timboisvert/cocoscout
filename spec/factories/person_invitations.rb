FactoryBot.define do
  factory :person_invitation do
    sequence(:email) { |n| "person#{n}@example.com" }
    association :production_company
    token { SecureRandom.hex(20) }
  end
end
