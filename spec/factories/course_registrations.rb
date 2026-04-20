# frozen_string_literal: true

FactoryBot.define do
  factory :course_registration do
    association :course_offering
    association :person
    amount_cents { 5000 }
    status { "confirmed" }
    registered_at { Time.current }
    paid_at { Time.current }
  end
end
