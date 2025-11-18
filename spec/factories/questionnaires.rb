FactoryBot.define do
  factory :questionnaire do
    association :production
    title { "Sample Questionnaire" }
    instruction_text { "<p>Please answer the following questions</p>" }
    accepting_responses { true }
    include_availability_section { false }
    require_all_availability { false }
    availability_show_ids { [] }
  end
end
