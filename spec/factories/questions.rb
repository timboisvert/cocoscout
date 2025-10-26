FactoryBot.define do
  factory :question do
    association :questionable, factory: :call_to_audition
    text { "What is your favorite color?" }
    question_type { "short_text" }
    required { false }

    trait :required do
      required { true }
    end

    trait :long_text do
      question_type { "long_text" }
      text { "Tell us about yourself" }
    end

    trait :multiple_choice do
      question_type { "multiple_choice" }
      text { "Which option do you prefer?" }
    end
  end
end
