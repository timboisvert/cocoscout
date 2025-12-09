# frozen_string_literal: true

FactoryBot.define do
  factory :email_log do
    association :user
    recipient { Faker::Internet.email }
    subject { Faker::Lorem.sentence }
    body { "<p>#{Faker::Lorem.paragraph}</p>" }
    mailer_class { "TestMailer" }
    mailer_action { "test_action" }
    message_id { Faker::Internet.uuid }
    sent_at { Time.current }
    delivery_status { "queued" }
  end
end
