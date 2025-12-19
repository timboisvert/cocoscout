# frozen_string_literal: true

FactoryBot.define do
  factory :group_invitation do
    association :group
    association :invited_by, factory: :person
    sequence(:name) { |n| "Invited Person #{n}" }
    sequence(:email) { |n| "invited#{n}@example.com" }
    permission_level { :write }
    token { SecureRandom.hex(20) }
    accepted_at { nil }

    trait :accepted do
      accepted_at { Time.current }
    end

    trait :pending do
      accepted_at { nil }
    end

    trait :owner do
      permission_level { :owner }
    end

    trait :viewer do
      permission_level { :view }
    end
  end
end
