# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Pro #{n}" }
    association :owner, factory: :user

    # On the Pro plan (via comp) — unlocks the paid modules and removes the
    # monthly event cap. Use in specs that exercise Money/Staffing/Documents/
    # Auditions/Casting Table, which are gated to Pro.
    trait :pro do
      comped_indefinitely { true }
    end
  end
end
