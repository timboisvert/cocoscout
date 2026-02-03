# frozen_string_literal: true

FactoryBot.define do
  factory :content_template do
    sequence(:key) { |n| "template_#{n}" }
    sequence(:name) { |n| "Template #{n}" }
    subject { "Test Subject with {{recipient_name}}" }
    body { "Hello {{recipient_name}}, this is a test email about {{topic}}." }
    description { "A test content template" }
    category { "notification" }
    channel { :email }
    active { true }
    available_variables do
      [
        { name: "recipient_name", description: "Name of the recipient" },
        { name: "topic", description: "The topic of the content" }
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

    trait :message_channel do
      channel { :message }
    end

    trait :both_channels do
      channel { :both }
    end

    # Alias for backwards compatibility
    factory :email_template
  end
end
