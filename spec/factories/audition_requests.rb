# frozen_string_literal: true

FactoryBot.define do
  factory :audition_request do
    association :audition_cycle
    association :requestable, factory: :person
    status { :pending }

    trait :with_video do
      video_url { 'https://youtube.com/watch?v=abc123' }
    end

    trait :approved do
      status { :approved }
    end

    trait :rejected do
      status { :rejected }
    end
  end
end
