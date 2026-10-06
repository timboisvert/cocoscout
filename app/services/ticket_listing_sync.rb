# frozen_string_literal: true

# A contract answers the Tickets question for its production (Round 9 §3).
# When we sell the tickets and the contract says "on CocoScout", the
# production's ticketing setup (ProductionTicketing) takes the contract's
# ticket types (price and seats), its discount codes, and its ticketed nights
# as dates; on "put them on sale" the nights go on sale (and the organization's
# box office opens if it wasn't), on "set it up" they wait for the manager to
# turn the production on. When tickets aren't on CocoScout (we sell them
# elsewhere, or they sell), the production points at the link instead. Runs
# when the contract is activated and again whenever it's amended.
#
# Manners: a manager's own setup is never overwritten. A setup that already
# covers the nights (all performances, or their event type) is left matching
# that way; a hand-picked one gets the contract's nights added, and loses only
# the nights this contract itself added that have since left the deal. Dates
# the contract lists carry its id (ticket_listings.contract_id).
#
# Nothing a buyer bought ever changes:
#   - prices follow the contract for sales from now on; a date's seats never
#     drop below what it already sold;
#   - a type the contract dropped goes from every date, kept (no longer sold)
#     only where a ticket was bought on it;
#   - the contract's codes are added and kept up to date, never removed —
#     codes a manager added are theirs;
#   - a night that left the contract leaves Ticketing only while nobody has
#     bought for it (one with orders stays; cancel it to refund them).
# Rehearsals and other nights outside the deal are never picked.
class TicketListingSync
  Tier = Data.define(:name, :price_cents, :quantity)

  def self.for_contract(contract)
    new(contract).call
  end

  def initialize(contract)
    @contract = contract
    @organization = contract.organization
  end

  # The production's setup when the contract sells on CocoScout; otherwise
  # the production's outside link (or "no tickets") is recorded and nil comes back.
  def call
    production = @contract.production
    return nil unless production

    unless enabled?
      answer_outside!(production)
      return nil
    end

    tiers = contract_tiers
    return nil if tiers.empty?

    # Fresh: the contract's production may hold a copy loaded before a
    # manager switched the setup on.
    setup = ProductionTicketing.for(production).reload
    ids = ticketed_shows.pluck(:id)
    ProductionTicketing.transaction do
      pick_dates(setup, ids)
      sync_tiers(setup, tiers)
      sync_codes(setup)
      setup.update!(enabled: true) if @contract.cocoscout_ticketing_mode == "on_sale" && !setup.enabled?
      production.update!(tickets_mode: "cocoscout", tickets_url: nil)
      TicketingProfile.for(@organization).update!(enabled: true) if setup.enabled?
    end
    ProductionTicketingSync.sync_all!(setup)
    ProductionTicketingDates.switch!(setup, on: true) if setup.enabled?
    ProductionTicketingDates.sync!(setup)
    TicketListing.where(show_id: ids, contract_id: nil).update_all(contract_id: @contract.id)
    setup
  end

  def enabled?
    @contract.org_sells_tickets? &&
      @contract.cocoscout_ticketing_mode != "none" &&
      @organization&.feature_available?(:ticketing)
  end

  private

  # The deal's performances, canceled ones aside: never a rehearsal.
  def ticketed_shows
    @contract.deal_shows_scope(@contract.contract_shows.where(canceled: false))
             .where(event_type: EventTypes.revenue_event_types)
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

  # The setup's types follow the contract's, matched by name. A type the
  # contract dropped goes; its copies on the dates retire on sync.
  def sync_tiers(setup, tiers)
    existing = setup.ticket_tiers.to_a.index_by { |tier| tier.name.downcase }
    tiers.each_with_index do |tier, position|
      record = existing.delete(tier.name.downcase)
      if record
        record.update!(price_cents: tier.price_cents, quantity: tier.quantity, position: position)
      else
        setup.ticket_tiers.create!(name: tier.name, price_cents: tier.price_cents, quantity: tier.quantity, position: position)
      end
    end
    existing.each_value(&:destroy!)
  end

  # The contract's nights join the setup. A setup already covering them (all
  # performances, or by event type) is left as it is; a hand-picked one
  # (or a fresh one) gets them added, and loses only the nights this contract
  # itself added that have since left the deal.
  def pick_dates(setup, ids)
    fresh = setup.ticket_tiers.none? && setup.production_ticketing_shows.none? && !setup.enabled?
    setup.update!(event_matching: "manual") if fresh
    return unless setup.event_matching == "manual"

    left = TicketListing.where(contract_id: @contract.id).where.not(show_id: ids).pluck(:show_id)
    setup.production_ticketing_shows.where(show_id: left).delete_all if left.any?
    (ids - setup.production_ticketing_shows.pluck(:show_id)).each { |id| setup.production_ticketing_shows.create!(show_id: id) }
  end

  # Not on CocoScout: the production points where tickets are sold (we sell
  # them elsewhere, or they sell), or says there are none. A manager's own
  # later answer isn't overwritten; a link always is recorded.
  def answer_outside!(production)
    url = @contract.outside_tickets_url
    if url
      site = TicketLink.recognize(url)
      return unless site

      source = @organization.ticket_sources.find_by("LOWER(name) = ?", site[:name].downcase) ||
               @organization.ticket_sources.create!(name: site[:name], position: @organization.ticket_sources.count)
      source.restore! if source.archived?
      production.update!(tickets_mode: "elsewhere", tickets_url: site[:url])
    elsif production.tickets_mode == "unset"
      production.update!(tickets_mode: (@contract.who_sells_tickets.present? ? "elsewhere" : "none"))
    end
  end

  # The contract's codes, good for every date of the production. A code
  # limited to some types names the setup's types; a date's copies match
  # through their source (TicketDiscountCode#applies_to?).
  def sync_codes(setup)
    Contract.ticketing_discounts(@contract.draft_ticketing).each do |discount|
      code = discount["code"].to_s.strip.upcase
      amount = discount["amount"].to_d
      next if code.empty? || amount <= 0

      percent = discount["amount_type"] == "percent"
      tier_ids = if discount["applies_to"] == "specific"
        names = Array(discount["tier_names"]).map { |name| name.to_s.downcase }
        setup.ticket_tiers.reload.select { |tier| names.include?(tier.name.downcase) }.map(&:id)
      else
        []
      end

      record = @organization.ticket_discount_codes.find_or_initialize_by(code: code, production: setup.production)
      record.assign_attributes(kind: percent ? "percent" : "fixed",
                               percent: percent ? amount : nil, amount_cents: percent ? nil : (amount * 100).round.to_i,
                               ticket_tier_ids: tier_ids, active: true)
      record.save!
    end
  end
end
