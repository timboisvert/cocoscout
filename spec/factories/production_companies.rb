FactoryBot.define do
  factory :production_company do
    sequence(:name) { |n| "Production Company #{n}" }
  end
end
