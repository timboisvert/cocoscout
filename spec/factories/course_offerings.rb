# frozen_string_literal: true

FactoryBot.define do
  factory :course_offering do
    association :production
    sequence(:title) { |n| "Course #{n}" }
    price_cents { 5000 }
    currency { "usd" }
    status { :open }
  end
end
