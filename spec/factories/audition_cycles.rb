# frozen_string_literal: true

FactoryBot.define do
  factory :audition_cycle do
    association :production
    opens_at { 1.day.ago }
    closes_at { 1.week.from_now }
    audition_type { :in_person }
    allow_in_person_auditions { true }
    allow_video_submissions { false }
    token { SecureRandom.urlsafe_base64(12) }

    trait :video_upload do
      audition_type { :video_upload }
      allow_in_person_auditions { false }
      allow_video_submissions { true }
    end

    trait :hybrid do
      allow_in_person_auditions { true }
      allow_video_submissions { true }
    end

    trait :upcoming do
      opens_at { 1.day.from_now }
      closes_at { 1.week.from_now }
    end

    trait :closed do
      opens_at { 2.weeks.ago }
      closes_at { 1.week.ago }
    end

    trait :open_ended do
      opens_at { 1.day.ago }
      closes_at { nil }
    end
  end
end
