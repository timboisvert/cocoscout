FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Production Company #{n}" }
  end
end
