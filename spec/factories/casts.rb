FactoryBot.define do
  factory :cast do
    association :production
    sequence(:name) { |n| "Cast #{n}" }
  end
end
