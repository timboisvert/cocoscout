# frozen_string_literal: true

FactoryBot.define do
  factory :email_template do
    sequence(:key) { |n| "template_#{n}" }
    sequence(:name) { |n| "Template #{n}" }
    subject { "Test Subject with {{recipient_name}}" }
    body { "Hello {{recipient_name}}, this is a test email about {{topic}}." }
    description { "A test email template" }
    category { "notification" }
    active { true }
    available_variables do
      [
        { name: "recipient_name", description: "Name of the recipient" },
        { name: "topic", description: "The topic of the email" }
      ]
    end

    trait :inactive do
      active { false }
    end

    trait :invitation do
      category { "invitation" }
    end

    trait :system do
      category { "system" }
    end
  end
end
