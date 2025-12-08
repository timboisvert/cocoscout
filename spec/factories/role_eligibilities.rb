# frozen_string_literal: true

FactoryBot.define do
  factory :role_eligibility do
    association :role
    association :member, factory: :person
  end
end
