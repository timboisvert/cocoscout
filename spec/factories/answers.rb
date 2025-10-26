FactoryBot.define do
  factory :answer do
    association :question
    association :audition_request
    value { "This is my answer" }
  end
end
