FactoryBot.define do
  factory :production do
    association :production_company
    sequence(:name) { |n| "Production #{n}" }
    contact_email { "contact@example.com" }
  end
end
