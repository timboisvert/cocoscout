# frozen_string_literal: true

FactoryBot.define do
  factory :questionnaire do
    association :production
    organization { production&.organization || association(:organization) }
    title { 'Sample Questionnaire' }
    instruction_text { '<p>Please answer the following questions</p>' }
    accepting_responses { true }
  end
end
