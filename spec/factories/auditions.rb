# frozen_string_literal: true

FactoryBot.define do
  factory :audition do
    association :person
    association :audition_request
    association :audition_session
  end
end
