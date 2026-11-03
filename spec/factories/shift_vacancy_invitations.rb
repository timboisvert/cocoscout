# frozen_string_literal: true

FactoryBot.define do
  factory :shift_vacancy_invitation do
    association :shift_vacancy
    association :person
    invited_at { Time.current }

    trait :claimed do
      claimed_at { Time.current }
    end
  end
end
