# frozen_string_literal: true

FactoryBot.define do
  factory :show_person_role_assignment do
    association :show
    association :person
    association :role
  end
end
