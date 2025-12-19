# frozen_string_literal: true

FactoryBot.define do
  factory :profile_headshot do
    association :profileable, factory: :person
    position { 0 }
    is_primary { false }
    category { nil }

    trait :primary do
      is_primary { true }
    end

    trait :theatrical do
      category { "theatrical" }
    end

    trait :commercial do
      category { "commercial" }
    end

    trait :with_image do
      after(:build) do |headshot|
        headshot.image.attach(
          io: StringIO.new("fake image data"),
          filename: "headshot.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
