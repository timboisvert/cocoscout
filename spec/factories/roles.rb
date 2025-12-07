# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    association :production
    sequence(:name) { |n| "Role #{n}" }
  end
end
