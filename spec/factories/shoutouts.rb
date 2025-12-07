# frozen_string_literal: true

FactoryBot.define do
  factory :shoutout do
    association :author, factory: :person
    association :shoutee, factory: :person
    content { 'This is a great shoutout message for testing purposes!' }
  end
end
