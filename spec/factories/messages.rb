# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    association :sender, factory: :user
    association :organization
    sequence(:subject) { |n| "Test Message #{n}" }
    body { "This is a test message body." }
    visibility { :personal }
    message_type { :direct }

    trait :with_production do
      association :production
    end

    trait :with_show do
      association :show
      visibility { :show }
    end

    trait :production_visible do
      association :production
      visibility { :production }
    end

    trait :cast_contact do
      message_type { :cast_contact }
    end

    trait :talent_pool do
      message_type { :talent_pool }
    end

    trait :system do
      message_type { :system }
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :with_recipients do
      transient do
        recipient_count { 2 }
      end

      after(:create) do |message, evaluator|
        evaluator.recipient_count.times do
          person = create(:person, user: create(:user))
          message.message_recipients.create!(recipient: person)
        end
      end
    end

    trait :as_reply do
      transient do
        parent { nil }
      end

      after(:build) do |message, evaluator|
        if evaluator.parent
          message.parent_message = evaluator.parent
          message.production = evaluator.parent.production
          message.show = evaluator.parent.show
          message.visibility = evaluator.parent.visibility
          message.organization = evaluator.parent.organization
        end
      end
    end
  end

  factory :message_recipient do
    association :message
    association :recipient, factory: :person
    read_at { nil }
    archived_at { nil }
  end

  factory :message_subscription do
    association :message
    association :user
    last_read_at { nil }
    muted { false }
  end

  factory :message_reaction do
    association :message
    association :user
    emoji { "👍" }
  end

  factory :message_regard do
    association :message
    association :regardable, factory: :production
  end
end
