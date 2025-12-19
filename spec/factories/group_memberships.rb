# frozen_string_literal: true

FactoryBot.define do
  factory :group_membership do
    association :group
    association :person
    permission_level { :write }
    show_on_profile { true }
  end
end
