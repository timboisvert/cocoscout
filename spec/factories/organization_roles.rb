FactoryBot.define do
  factory :organization_role do
    association :user
    association :organization
    company_role { "viewer" }

    trait :manager do
      company_role { "manager" }
    end
  end
end
