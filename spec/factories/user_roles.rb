FactoryBot.define do
  factory :user_role do
    association :user
    association :production_company
    role { "viewer" }

    trait :manager do
      role { "manager" }
    end
  end
end
