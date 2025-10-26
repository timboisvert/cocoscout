FactoryBot.define do
  factory :role do
    association :production
    sequence(:name) { |n| "Role #{n}" }
  end
end
