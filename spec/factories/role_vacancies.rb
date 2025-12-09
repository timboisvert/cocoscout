# frozen_string_literal: true

FactoryBot.define do
  factory :role_vacancy do
    association :show
    association :role
    status { "open" }

    trait :with_vacated_by do
      association :vacated_by, factory: :person
      vacated_at { Time.current }
    end

    trait :with_reason do
      reason { "Personal conflict with schedule" }
    end

    trait :filled do
      status { "filled" }
      association :filled_by, factory: :person
      filled_at { Time.current }
      closed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
      closed_at { Time.current }
    end
  end
end
