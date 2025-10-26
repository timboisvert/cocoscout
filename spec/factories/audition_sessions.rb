FactoryBot.define do
  factory :audition_session do
    association :production
    association :location
    start_at { 1.week.from_now }
    end_at { 1.week.from_now + 2.hours }
    maximum_auditionees { 10 }

    trait :past do
      start_at { 1.week.ago }
      end_at { 1.week.ago + 2.hours }
    end

    trait :upcoming do
      start_at { 1.week.from_now }
      end_at { 1.week.from_now + 2.hours }
    end
  end
end
