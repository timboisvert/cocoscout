# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    association :production
    sequence(:name) { |n| "Role #{n}" }

    trait :restricted do
      restricted { true }

      after(:create) do |role|
        # Create an eligible person to satisfy validation
        person = create(:person)
        create(:role_eligibility, role: role, member: person)
      end
    end

    # For tests that need to control eligibility themselves
    trait :restricted_no_validation do
      restricted { true }

      to_create do |instance|
        instance.save(validate: false)
      end
    end
  end
end
