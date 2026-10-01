# frozen_string_literal: true

# Puts several of a production's dates on sale in one go: a listing per show,
# each with the same ticket prices. Shows that already have a listing are left
# alone. Listings start as drafts unless the manager chose to open sales.
class TicketListingBuilder
  Result = Data.define(:created, :skipped)
  Tier = Data.define(:name, :price_cents, :quantity)

  def self.create_for!(shows:, tiers:, status: "draft", on_sale_at: nil)
    raise ArgumentError, "Add at least one ticket price" if tiers.empty?
    raise ArgumentError, "Pick at least one date" if shows.empty?

    created = []
    skipped = []
    TicketListing.transaction do
      shows.each do |show|
        if TicketListing.exists?(show_id: show.id)
          skipped << show
          next
        end

        listing = TicketListing.create!(show: show, status: status, on_sale_at: on_sale_at)
        tiers.each_with_index do |tier, position|
          listing.ticket_tiers.create!(name: tier.name, price_cents: tier.price_cents, quantity: tier.quantity, position: position)
        end
        created << listing
      end
    end
    Result.new(created: created, skipped: skipped)
  end

  # Form rows → tiers. A row with neither a name nor a price is ignored; a
  # price without a name is "General admission". Prices read like people type
  # them: "20", "$20.00", "19.5".
  def self.parse_tiers(rows)
    Array(rows).filter_map do |row|
      row = row.to_h.symbolize_keys
      name = row[:name].to_s.squish
      price_text = row[:price].to_s.delete("$,").strip
      next if name.empty? && price_text.empty?

      price_cents = price_text.empty? ? 0 : (BigDecimal(price_text) * 100).round.to_i
      raise ArgumentError, "Prices can't be negative" if price_cents.negative?

      seats = row[:quantity].to_s.strip
      quantity = seats.empty? ? nil : Integer(seats, 10)
      raise ArgumentError, "Seats must be at least 1" if quantity && quantity < 1

      Tier.new(name: name.presence || "General admission", price_cents: price_cents, quantity: quantity)
    end
  rescue ArgumentError, TypeError => e
    raise ArgumentError, e.message.match?(/\A(Prices|Seats)/) ? e.message : "Check the ticket prices and seats — use numbers like 20 or 19.50"
  end
end
