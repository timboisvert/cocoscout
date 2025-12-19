# frozen_string_literal: true

FactoryBot.define do
  factory :email_log do
    association :user
    sequence(:recipient) { |n| "recipient#{n}@example.com" }
    subject { "Test Email Subject" }
    mailer_class { "ApplicationMailer" }
    mailer_action { "send_email" }
    delivery_status { "pending" }
    sent_at { nil }

    trait :sent do
      sent_at { Time.current }
      delivery_status { "delivered" }
    end

    trait :delivered do
      sent_at { Time.current }
      delivery_status { "delivered" }
    end

    trait :failed do
      sent_at { Time.current }
      delivery_status { "failed" }
    end

    trait :pending do
      sent_at { nil }
      delivery_status { "pending" }
    end
  end
end
