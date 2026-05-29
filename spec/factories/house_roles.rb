# frozen_string_literal: true

FactoryBot.define do
  factory :house_role do
    association :organization
    sequence(:name) { |n| "House Role #{n}" }
    default_required_count { 1 }
    default_start_offset_minutes { -60 }
    default_end_offset_minutes { 60 }
    position { 0 }
  end
end
