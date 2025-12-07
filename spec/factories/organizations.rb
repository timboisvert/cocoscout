# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Production Company #{n}" }
    association :owner, factory: :user
  end
end
