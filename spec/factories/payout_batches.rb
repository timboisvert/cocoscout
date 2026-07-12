# frozen_string_literal: true

FactoryBot.define do
  factory :payout_batch do
    association :organization
    trigger { "manual" }
    status { "draft" }
    kind { "balance" }
  end
end
