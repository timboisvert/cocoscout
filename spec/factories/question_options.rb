FactoryBot.define do
  factory :question_option do
    association :question
    sequence(:text) { |n| "Option #{n}" }
  end
end
