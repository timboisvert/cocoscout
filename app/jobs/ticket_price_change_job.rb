# frozen_string_literal: true

# Every hour: for each date whose production has pricing rules, note each
# ticket type whose price in effect differs from the last one logged (or
# the list price, before any flip). The log is what the date page and
# Reports show; the price itself is read live by TicketPricing.
class TicketPriceChangeJob < ApplicationJob
  queue_as :default

  def perform
    ProductionTicketing.joins(:price_rules).merge(TicketPriceRule.enabled).distinct.includes(:production).find_each do |setup|
      setup.production.ticket_listings.on_sale_now.includes(:show, :ticket_tiers).find_each do |listing|
        listing.ticket_tiers.active.each do |tier|
          now = TicketPricing.current_price_cents(listing, tier)
          last = TicketPriceChange.where(ticket_listing: listing, ticket_tier: tier).recent.first
          was = last ? last.to_cents : tier.price_cents
          next if now == was

          rule = TicketPricing.rule_for(listing, tier)
          TicketPriceChange.create!(organization: listing.organization, ticket_listing: listing, ticket_tier: tier,
                                    ticket_price_rule: rule, from_cents: was, to_cents: now)
        end
      end
    end
  end
end
