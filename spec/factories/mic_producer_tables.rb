# frozen_string_literal: true

FactoryBot.define do
  factory :mic_producer do
    association :mic
    association :user
    role { :producer }
    accepted_at { Time.current }
  end

  factory :mic_claim do
    association :mic
    association :claimant, factory: :user
    status { :pending }
    role { :producer }
    proof { { "email" => "producer@example.com" } }
  end

  factory :mic_challenge do
    association :mic
    association :challenger, factory: :user
    reason { "I actually run this mic." }
    status { :pending }
  end

  factory :mic_suggestion do
    association :mic
    submitter_email { "fan@example.com" }
    note { "Time changed to 8pm." }
    status { :pending }
  end

  factory :city_hub_membership do
    association :city_hub
    association :user
    role { :editor }
  end

  factory :mic_announcement do
    association :mic
    association :posted_by, factory: :user
    title { "An update" }
    body  { "Mic is on as planned." }
    notify_subscribers { false }
    posted_at { Time.current }
  end

  factory :city_vote do
    sequence(:city) { |n| "Springfield #{n}" }
    state { "OH" }
    email { "fan@example.com" }
  end
end
