# frozen_string_literal: true

FactoryBot.define do
  factory :mic do
    association :venue
    sequence(:name) { |n| "Open Mic #{n}" }
    status { :active }
    format { :standup }
    signup_method { :in_person }
    bucket_draw { true }
    day_of_week { 1 }
    starts_local_time { "20:00" }
    cost { :free }
    spot_length_minutes { 5 }
    signup_opens_at_text { "Walk-in 7:30 PM" }
    blurb { "Long-running weekly mic." }

    trait :linked do
      transient do
        production { nil }
      end
      after(:build) do |mic, evaluator|
        mic.production = evaluator.production || create(:production)
      end
    end
  end

  factory :mic_tag do
    sequence(:slug) { |n| "tag-#{n}" }
    sequence(:name) { |n| "Tag #{n}" }
  end

  factory :mic_tagging do
    association :mic
    association :mic_tag
  end

  factory :city_hub do
    sequence(:slug) { |n| "city-#{n}" }
    sequence(:name) { |n| "City #{n}" }
    state { "IL" }
    timezone { "America/Chicago" }
    default_radius_miles { 25 }
    status { :draft }

    trait :active do
      status { :active }
      intro_markdown { "# Welcome\nGet up and try a 5." }
    end
  end

  factory :mic_edit do
    association :mic
    source { :system }
    field { "created" }
    new_value { "seeded" }
  end
end
