# frozen_string_literal: true

# The door on show night: checking people in, and selling or comping at the
# door. Check-in is one atomic update, so two phones scanning the same ticket
# can never both admit it.
class TicketDoor
  # What a scan or a tap at the door comes to. kind is one of:
  #   :admitted   — in you go
  #   :already    — this ticket was used (when and by whom are on it)
  #   :wrong_show — a real ticket, for another show
  #   :not_valid  — refunded, voided, or never paid for
  #   :not_found  — no ticket with that code
  Result = Data.define(:kind, :ticket, :message)

  UNDO_WINDOW = 2.minutes

  def initialize(listing, user)
    @listing = listing
    @user = user
  end

  # A scanned QR (its /tickets/v/<code> link, or the bare code) or a barcode from
  # another site.
  def check_in(scanned)
    code = scanned.to_s.strip
    code = code.split("/v/").last.to_s.split(/[?#]/).first.to_s if code.include?("/v/")
    return result(:not_found, nil, "No ticket with that code") if code.empty?

    ticket = Ticket.find_by(code: code) || Ticket.find_by(ticket_listing_id: @listing.id, external_barcode: code)
    return result(:not_found, nil, "No ticket with that code") unless ticket

    admit(ticket)
  end

  def admit(ticket)
    if ticket.ticket_listing_id != @listing.id
      other = ticket.ticket_listing
      return result(:wrong_show, ticket, "This ticket is for #{other.display_title}, #{other.starts_at&.strftime('%a %b %-d, %-l:%M %p')}")
    end

    changed = Ticket.where(id: ticket.id, status: "valid")
                    .update_all(status: "checked_in", checked_in_at: Time.current, checked_in_by_id: @user&.id, updated_at: Time.current)
    ticket.reload
    return result(:admitted, ticket, "Admitted — #{ticket.ticket_tier.name}") if changed == 1

    case ticket.status
    when "checked_in"
      who = ticket.checked_in_by&.person&.name || ticket.checked_in_by&.email_address
      result(:already, ticket, "Already checked in at #{ticket.checked_in_at.strftime('%-l:%M %p')}#{" by #{who}" if who}")
    else
      message = { "reserved" => "This ticket was never paid for", "exchanged" => "This ticket moved to another date" }
      result(:not_valid, ticket, message.fetch(ticket.status, "This ticket was refunded"))
    end
  end

  # Everyone on an order at once — a party of four walking in together.
  def check_in_order(order)
    raise ArgumentError, "order is for another show" unless order.ticket_listing_id == @listing.id

    order.tickets.where(status: "valid").map { |ticket| admit(ticket) }
  end

  # A mistaken check-in, put right. Door staff can undo their own for a couple
  # of minutes; managers any time.
  def undo(ticket, manager: false)
    return false unless ticket.ticket_listing_id == @listing.id && ticket.checked_in?
    return false unless manager || (ticket.checked_in_by_id == @user&.id && ticket.checked_in_at > UNDO_WINDOW.ago)

    Ticket.where(id: ticket.id, status: "checked_in")
          .update_all(status: "valid", checked_in_at: nil, checked_in_by_id: nil, updated_at: Time.current) == 1
  end

  # Walk-ups paying cash, or comps — recorded so the count, the show's
  # financials and the books see everyone. No fees: the money never touches
  # CocoScout. They're checked in on the spot.
  # products: { product_id => count } bought along with cash tickets; a comp
  # carries none (a bottle is never comped from here).
  def sell(quantities, kind:, buyer_name: nil, products: {})
    raise ArgumentError, "kind must be cash or comp" unless %w[cash comp].include?(kind)
    raise TicketCheckout::Error, "This show was canceled." if @listing.status == "canceled" || @listing.show.canceled

    tiers = @listing.ticket_tiers.active.index_by(&:id)
    requests = quantities.to_h.filter_map { |tier_id, count|
      tier = tiers[tier_id.to_i]
      count = count.to_i
      [ tier, count ] if tier && count.positive?
    }.to_h
    raise TicketCheckout::Error, "Pick at least one ticket." if requests.empty?

    order = nil
    seats = TicketCheckout.seat_requests(requests)
    Ticketing::Inventory.reserve!(@listing, seats) do
      order = TicketOrder.create!(organization: @listing.organization, ticket_listing: @listing, status: "paid", paid_at: Time.current,
                                  channel: kind == "cash" ? "door_cash" : "comp", money_path: kind == "cash" ? "cash" : "none",
                                  fee_mode: @listing.effective_fee_mode, buyer_name: buyer_name.to_s.squish.presence)
      # A 4-pack sold at the door is four tickets, everyone checked in.
      requests.each do |tier, count|
        count.times do
          tier.seat_prices.each do |cents|
            ticket = order.tickets.create!(ticket_tier: tier.base_tier, bundle_tier: (tier if tier.bundle?), ticket_listing: @listing,
                                           status: "checked_in", checked_in_at: Time.current, checked_in_by: @user, price_cents: cents,
                                           discount_cents: kind == "comp" ? cents : 0)
            record_tax(order, ticket) if kind == "cash"
          end
        end
      end
      if kind == "cash" && products.present?
        # A hold's items start "reserved"; a cash sale is paid on the spot.
        order.update_columns(status: "pending")
        TicketCheckout.set_items!(order, products, reprice: false)
        order.update_columns(status: "paid")
        order.ticket_order_items.update_all(status: "valid", updated_at: Time.current)
      end
      TicketCheckout.price!(order)
      post_cash_sale!(order) if kind == "cash"
    end
    TicketSalesSync.sync!(@listing.show)
    TicketingAfterSaleJob.perform_later(order.id)
    order
  rescue Ticketing::Inventory::SoldOut
    raise TicketCheckout::Error, "That's more than the seats left. Raise the seats on the show if the room has space."
  end

  def counts
    tickets = Ticket.where(ticket_listing_id: @listing.id)
    {
      checked_in: tickets.where(status: "checked_in").count,
      sold: tickets.where(status: Ticket::SOLD_STATUSES).count,
      capacity: @listing.inventory.capacity
    }
  end

  private

  def result(kind, ticket, message)
    Result.new(kind: kind, ticket: ticket, message: message)
  end

  def record_tax(order, ticket)
    tax = TaxCalculator.for_ticket(@listing, ticket.ticket_tier, ticket.price_cents)
    tax.lines.each do |line|
      TaxLine.create!(organization_id: order.organization_id, taxable: ticket, tax_rate: line.tax_rate, name: line.name,
                      rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter, included: line.included,
                      exempt: line.exempt, exemption_reason: line.exemption_reason, base_cents: line.base_cents,
                      tax_cents: line.tax_cents, sale_date: Date.current, event_date: @listing.starts_at&.to_date)
    end
    ticket.update_columns(tax_cents: tax.tax_cents)
  end

  # Cash in the box: the books only (it never touches the CocoScout balance).
  # The show is happening, so it's income now, not an advance sale.
  def post_cash_sale!(order)
    return unless order.total_cents.positive?

    lines = TicketOrderSettlement.sale_lines(order).map do |line|
      case line[:account]
      when :cocoscout_balance then line.merge(account: :door_cash, amount_cents: order.total_cents)
      when :advance_ticket_sales then line.merge(account: :ticket_income)
      when :advance_product_sales then line.merge(account: :product_income)
      else line
      end
    end
    LedgerPosting.post!(organization: order.organization, source: order, kind: "sale",
                        entry_date: Date.current, cash_date: Date.current,
                        memo: "Door sale #{order.code}", lines: lines)
  end
end
