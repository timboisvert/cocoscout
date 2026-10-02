# frozen_string_literal: true

# Keeps a contract's deal on CocoScout Ticketing, when the contract says we
# sell the tickets and the manager ticked "Sell these on CocoScout
# Ticketing": the production's ticketing setup (ProductionTicketing) takes the
# contract's ticket types (price and seats), its discount codes, and its
# ticketed nights as the dates picked. Runs when the contract is activated
# and again whenever it's amended.
#
# Nothing goes on sale by itself: the manager turns the production's
# ticketing on in Ticketing. Once it's on, every date follows the setup
# (ProductionTicketingDates), and nothing a buyer bought ever changes:
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

  # The production's setup, or nil when the contract doesn't sell here.
  def call
    return nil unless enabled? && @contract.production

    tiers = contract_tiers
    return nil if tiers.empty?

    # Fresh: the contract's production may hold a copy loaded before a
    # manager switched the setup on.
    setup = ProductionTicketing.for(@contract.production).reload
    ProductionTicketing.transaction do
      setup.update!(event_matching: "manual")
      sync_tiers(setup, tiers)
      pick_dates(setup)
      sync_codes(setup)
    end
    ProductionTicketingSync.sync_all!(setup)
    ProductionTicketingDates.sync!(setup)
    setup
  end

  def enabled?
    @contract.org_sells_tickets? &&
      ActiveModel::Type::Boolean.new.cast(@contract.draft_ticketing["list_on_cocoscout"]) &&
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

  def pick_dates(setup)
    ids = ticketed_shows.pluck(:id)
    setup.production_ticketing_shows.where.not(show_id: ids).delete_all
    (ids - setup.production_ticketing_shows.pluck(:show_id)).each { |id| setup.production_ticketing_shows.create!(show_id: id) }
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
