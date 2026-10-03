# frozen_string_literal: true

FactoryBot.define do
  factory :ticket_listing do
    transient do
      organization { association(:organization) }
    end

    show { association(:show, production: association(:production, organization: organization)) }
    status { "on_sale" }
  end

  factory :ticket_tier do
    association :ticket_listing
    sequence(:name) { |n| "Tier #{n}" }
    price_cents { 2_000 }
  end

  factory :ticket_order do
    association :ticket_listing
    organization { ticket_listing.organization }
    fee_mode { "buyer" }
    status { "pending" }
    expires_at { TicketOrder::HOLD.from_now }
    buyer_name { "Avery Buyer" }
    buyer_email { "avery@example.com" }
  end

  factory :ticket do
    association :ticket_order
    ticket_listing { ticket_order.ticket_listing }
    ticket_tier { association(:ticket_tier, ticket_listing: ticket_listing) }
    price_cents { ticket_tier.price_cents }
    status { "valid" }
  end
end

FactoryBot.define do
  factory :ticket_product do
    association :organization
    sequence(:name) { |n| "Champagne bottle #{n}" }
    price_cents { 4_500 }
  end
end
