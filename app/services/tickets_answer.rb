# frozen_string_literal: true

# Applies a production's answer to the Tickets question (Round 9 §3):
#
#   cocoscout  set the production up to sell here: its ticket types, who pays
#              the fees, when sales open; every upcoming date is listed; the
#              organization's box office opens if it wasn't yet.
#   elsewhere  the link where people buy. The site is read from the link and
#              becomes a ticket source, so Sold elsewhere and the financials
#              worksheet already have its row.
#   none       free, or not ticketed. The nudges stop.
#
# Switching away from CocoScout stops the dates selling; it's refused while
# any of them has sold tickets (close sales in Ticketing first).
class TicketsAnswer
  class Error < StandardError; end

  Result = Struct.new(:mode, :site, :listings, keyword_init: true)

  def self.apply!(production, mode:, url: nil, tiers: [], fee_mode: nil, schedule_mode: nil, opens_days_before: nil)
    case mode.to_s
    when "cocoscout" then sell_here!(production, tiers: tiers, fee_mode: fee_mode, schedule_mode: schedule_mode, opens_days_before: opens_days_before)
    when "elsewhere" then elsewhere!(production, url)
    when "none" then none!(production)
    else raise Error, "Pick where people get tickets."
    end
  end

  def self.sell_here!(production, tiers:, fee_mode:, schedule_mode:, opens_days_before:)
    organization = production.organization
    raise Error, "Selling tickets on CocoScout is part of Pro." unless organization.feature_available?(:ticketing)

    setup = ProductionTicketing.for(production)
    attrs = { enabled: true }
    attrs[:fee_mode] = fee_mode if fee_mode.in?(TicketingProfile::FEE_MODES)
    attrs[:schedule_mode] = schedule_mode if schedule_mode.in?(ProductionTicketing::SCHEDULE_MODES)
    attrs[:opens_days_before] = opens_days_before.to_i if schedule_mode == "relative" && opens_days_before.to_i.positive?
    rows = tier_rows(tiers)
    raise Error, "Add at least one ticket type with a price." if setup.ticket_tiers.active.none? && rows.empty?

    ProductionTicketing.transaction do
      setup.update!(attrs)
      rows.each_with_index { |row, i| setup.ticket_tiers.create!(row.merge(position: i)) } if setup.ticket_tiers.active.none?
      production.update!(tickets_mode: "cocoscout", tickets_url: nil)
      TicketingProfile.for(organization).update!(enabled: true)
    end
    ProductionTicketingSync.sync_all!(setup)
    ProductionTicketingDates.switch!(setup, on: true)
    result = ProductionTicketingDates.sync!(setup)
    Result.new(mode: "cocoscout", listings: result)
  end

  def self.elsewhere!(production, url)
    site = TicketLink.recognize(url)
    raise Error, "Paste the link where people buy tickets." unless site

    stop_selling_here!(production)
    organization = production.organization
    source = organization.ticket_sources.find_by("LOWER(name) = ?", site[:name].downcase) ||
             organization.ticket_sources.create!(name: site[:name], position: organization.ticket_sources.count)
    source.restore! if source.archived?
    production.update!(tickets_mode: "elsewhere", tickets_url: site[:url])
    Result.new(mode: "elsewhere", site: site[:name])
  end

  def self.none!(production)
    stop_selling_here!(production)
    production.update!(tickets_mode: "none", tickets_url: nil)
    Result.new(mode: "none")
  end

  # Leaving CocoScout: the dates stop selling, unless people already hold tickets.
  def self.stop_selling_here!(production)
    setup = production.production_ticketing
    return unless setup&.enabled?

    if TicketOrder.paid_like.where(ticket_listing_id: setup.listings.select(:id)).exists?
      raise Error, "#{production.name} sells tickets on CocoScout and some are sold. Close its sales in Ticketing first."
    end

    setup.update!(enabled: false)
    ProductionTicketingDates.switch!(setup, on: false)
  end
  private_class_method :stop_selling_here!

  # [{ "name" => "General", "price" => "20", "seats" => "60" }] → attributes.
  def self.tier_rows(tiers)
    Array(tiers).map { |row| row.respond_to?(:to_h) ? row.to_h.stringify_keys : {} }.filter_map do |row|
      name = row["name"].to_s.squish
      cents = dollars_to_cents(row["price"])
      next if name.blank? || cents.nil?

      { name: name, price_cents: cents, quantity: row["seats"].to_s.strip.presence&.to_i }
    end
  end
  private_class_method :tier_rows

  def self.dollars_to_cents(text)
    cleaned = text.to_s.delete("$,").strip
    cleaned.empty? ? nil : (BigDecimal(cleaned) * 100).round.to_i
  rescue ArgumentError
    nil
  end
  private_class_method :dollars_to_cents
end
