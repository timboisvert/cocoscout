# frozen_string_literal: true

FactoryBot.define do
  factory :show_availability do
    association :person
    association :show
    status { :unset }

    trait :available do
      status { :available }
    end

    trait :unavailable do
      status { :unavailable }
    end
  end
end
