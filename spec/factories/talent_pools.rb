FactoryBot.define do
  factory :talent_pool do
    association :production
    sequence(:name) { |n| "Talent Pool #{n}" }
  end
end
