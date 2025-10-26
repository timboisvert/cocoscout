FactoryBot.define do
  factory :audition_request do
    association :call_to_audition
    association :person
    status { :unreviewed }

    trait :with_video do
      video_url { "https://youtube.com/watch?v=abc123" }
    end

    trait :undecided do
      status { :undecided }
    end

    trait :passed do
      status { :passed }
    end

    trait :accepted do
      status { :accepted }
    end
  end
end
