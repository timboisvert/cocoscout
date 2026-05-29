# frozen_string_literal: true

FactoryBot.define do
  factory :shift_assignment do
    association :shift
    association :person
    sequence(:position) { |n| n }
  end
end
