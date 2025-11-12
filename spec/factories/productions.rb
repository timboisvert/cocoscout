FactoryBot.define do
  factory :production do
    association :organization
    sequence(:name) { |n| "Production #{n}" }
    contact_email { "contact@example.com" }
  end
end
