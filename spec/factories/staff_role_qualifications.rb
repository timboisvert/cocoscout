# frozen_string_literal: true

FactoryBot.define do
  factory :staff_role_qualification do
    association :organization_staff_member
    association :house_role
  end
end
