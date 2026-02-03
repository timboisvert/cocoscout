# frozen_string_literal: true

FactoryBot.define do
  factory :sign_up_form_instance do
    sign_up_form
    association :show
    show_name { "Test Show" }
    show_date { 1.week.from_now }
    status { "open" }

    trait :closed do
      status { "closed" }
    end

    trait :scheduled do
      status { "scheduled" }
    end
  end
end
