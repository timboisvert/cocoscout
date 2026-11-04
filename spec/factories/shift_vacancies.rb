# frozen_string_literal: true

FactoryBot.define do
  factory :shift_vacancy do
    association :shift
    association :vacated_by, factory: :person
    vacated_at { Time.current }
    status { "open" }
  end
end
