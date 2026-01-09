# frozen_string_literal: true

FactoryBot.define do
  factory :talent_pool_share do
    association :talent_pool
    association :production

    # Ensure same organization by default
    after(:build) do |share|
      if share.production && share.talent_pool&.production
        share.production.organization = share.talent_pool.production.organization
      end
    end
  end
end
