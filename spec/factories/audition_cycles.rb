FactoryBot.define do
  factory :audition_cycle do
    association :production
    opens_at { 1.day.ago }
    closes_at { 1.week.from_now }
    audition_type { :in_person }
    token { SecureRandom.urlsafe_base64(12) }

    trait :video_upload do
      audition_type { :video_upload }
    end

    trait :upcoming do
      opens_at { 1.day.from_now }
      closes_at { 1.week.from_now }
    end

    trait :closed do
      opens_at { 2.weeks.ago }
      closes_at { 1.week.ago }
    end
  end
end
