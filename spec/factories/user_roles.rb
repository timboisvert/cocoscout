FactoryBot.define do
  factory :user_role do
    association :user
    association :production_company
    company_role { "viewer" }

    trait :manager do
      company_role { "manager" }
    end
  end
end
