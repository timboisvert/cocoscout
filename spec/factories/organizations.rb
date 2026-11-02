# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Pro #{n}" }
    association :owner, factory: :user
    # Books' categories are set up (BooksCategorySetup); a spec of the setup
    # itself passes nil.
    books_categories_set_up_at { Time.current }

    # On the Pro plan (via comp) — unlocks the paid modules and removes the
    # monthly event cap. Use in specs that exercise Money/Staffing/Documents/
    # Auditions/Casting Table, which are gated to Pro.
    trait :pro do
      comped_indefinitely { true }
    end
  end
end
