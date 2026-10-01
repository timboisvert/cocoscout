# frozen_string_literal: true

# Keeps a contract's ticketed shows listed on CocoScout Ticketing, when the
# contract says we sell the tickets and the manager ticked "Sell these on
# CocoScout Ticketing": a listing per show carrying the contract's ticket
# tiers (price and seats) and its discount codes. Runs when the contract is
# activated and again whenever it's amended.
#
# Nothing goes on sale by itself, and nothing a buyer bought ever changes:
#   - new shows get draft listings;
#   - prices follow the contract (for sales from now on); seats never drop
#     below what's already sold;
#   - a tier the contract dropped is archived if it sold, removed if not;
#   - codes from the contract are added and kept up to date, never removed —
#     codes a manager added on the listing are theirs;
#   - a show that left the contract takes its listing along only while nobody
#     has bought (one with orders is cancelled and refunded instead).
# Rehearsals and other nights outside the deal never get listings.
class TicketListingSync
  Tier = Data.define(:name, :price_cents, :quantity)

  def self.for_contract(contract)
    new(contract).call
  end

  def initialize(contract)
    @contract = contract
    @organization = contract.organization
  end

  def call
    return [] unless enabled?

    tiers = contract_tiers
    return [] if tiers.empty?

    shows = ticketed_shows.to_a
    listings = shows.map { |show| sync_listing(show, tiers) }
    remove_listings_for_departed_shows(shows)
    listings
  end

  def enabled?
    @contract.org_sells_tickets? &&
      ActiveModel::Type::Boolean.new.cast(@contract.draft_ticketing["list_on_cocoscout"]) &&
      @organization&.feature_available?(:ticketing)
  end

  private

  def ticketed_shows
    @contract.deal_shows_scope(@contract.contract_shows.where(canceled: false))
             .where(event_type: EventTypes.revenue_event_types)
             .where("date_and_time >= ?", Time.current)
             .includes(:ticket_listing)
  end

  def contract_tiers
    Array(@contract.draft_ticketing["tiers"]).filter_map do |tier|
      name = tier["name"].to_s.squish
      next if name.empty?

      seats = tier["quantity"].to_s.strip
      Tier.new(name: name, price_cents: (tier["price"].to_d * 100).round.to_i,
               quantity: seats.empty? ? nil : [ seats.to_i, 1 ].max)
    end
  end

  def sync_listing(show, tiers)
    listing = show.ticket_listing || TicketListing.create!(show: show, contract: @contract)
    listing.update!(contract: @contract) if listing.contract_id.nil?

    existing = listing.ticket_tiers.to_a.index_by { |tier| tier.name.downcase }
    tiers.each_with_index do |tier, position|
      record = existing.delete(tier.name.downcase)
      if record
        sold = record.sold_count
        record.update!(price_cents: tier.price_cents, position: position, archived_at: nil,
                       quantity: tier.quantity && [ tier.quantity, sold ].max)
      else
        listing.ticket_tiers.create!(name: tier.name, price_cents: tier.price_cents, quantity: tier.quantity, position: position)
      end
    end
    existing.each_value do |dropped|
      dropped.tickets.exists? ? dropped.update!(archived_at: Time.current) : dropped.destroy!
    end

    sync_codes(listing)
    listing
  end

  def sync_codes(listing)
    Contract.ticketing_discounts(@contract.draft_ticketing).each do |discount|
      code = discount["code"].to_s.strip.upcase
      amount = discount["amount"].to_d
      next if code.empty? || amount <= 0

      percent = discount["amount_type"] == "percent"
      tier_ids = if discount["applies_to"] == "specific"
        names = Array(discount["tier_names"]).map { |name| name.to_s.downcase }
        listing.ticket_tiers.select { |tier| names.include?(tier.name.downcase) }.map(&:id)
      else
        []
      end

      record = listing.ticket_discount_codes.find_or_initialize_by(code: code)
      record.assign_attributes(organization: @organization, kind: percent ? "percent" : "fixed",
                               percent: percent ? amount : nil, amount_cents: percent ? nil : (amount * 100).round.to_i,
                               ticket_tier_ids: tier_ids, active: true)
      record.save!
    end
  end

  def remove_listings_for_departed_shows(shows)
    @organization.ticket_listings.where(contract: @contract).where.not(show_id: shows.map(&:id))
                 .joins(:show).where("shows.date_and_time >= ?", Time.current)
                 .find_each do |listing|
      listing.destroy if listing.status == "draft" && !listing.ticket_orders.exists?
    end
  end
end
