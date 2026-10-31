# frozen_string_literal: true

module Ticketing
  # Group sales (advanced ticketing plan §3): a block of general-admission
  # seats held for a group, invoiced the moment it's booked, turned into
  # tickets when the invoice is paid (or early, for a trusted group), given
  # back when it isn't paid in time.
  #
  # The invoice is the money: it posts to the books as ticket income owed
  # (Invoice#post_to_books) and its payments land in the balance the way any
  # invoice's do (InvoiceCollection, Invoice#receive!). The ticket order is
  # the seats: channel "group", money_path "external", so settlement never
  # counts the money twice. Paid through our pay page, the block costs the
  # organization 50¢ a paid seat (fee!), like every sale through our
  # checkout (D4).
  class GroupSales
    class Error < StandardError; end

    FEE_CENTS = TicketPricing::PLATFORM_FEE_CENTS

    # Hold the seats, write the invoice, tell the leader.
    def self.book!(listing, attrs, by: nil)
      show = listing.show
      raise Error, "This show was canceled." if listing.status == "canceled" || show.canceled
      raise Error, "This show has already happened." if show.date_and_time < Time.current

      booking = listing.group_bookings.new(attrs)
      booking.organization = listing.organization
      booking.created_by = by
      booking.status = "booked"
      raise Error, booking.errors.full_messages.to_sentence unless booking.valid?
      raise Error, "Pick one of this date's ticket types." if booking.ticket_tier.ticket_listing_id != listing.id || booking.ticket_tier.bundle?

      Inventory.reserve!(listing, { booking.ticket_tier => booking.seats }) do
        booking.save!
        booking.create_quantity_hold!(organization: listing.organization, ticket_listing: listing, ticket_tier: booking.ticket_tier, quantity: booking.seats)
        booking.update!(invoice: build_invoice(booking))
      end
      TicketGroupMailer.booked(booking).deliver_later
      booking
    rescue Inventory::SoldOut
      left = listing.inventory.remaining(tier: attrs[:ticket_tier] || attrs["ticket_tier"])
      raise Error, left ? "Only #{left} #{'seat'.pluralize(left)} of that type are left; the block doesn't fit." : "The block doesn't fit in the seats left."
    end

    # The invoice: the paid seats a line, the chaperones a no-charge line.
    # Round numbers: the organization absorbs the fees on a group.
    def self.build_invoice(booking)
      listing = booking.ticket_listing
      show = listing.show
      night = "#{listing.display_title}, #{show.date_and_time.strftime('%A, %B %-d, %Y at %-l:%M %p')}"
      invoice = booking.organization.invoices.new(
        bill_to_name: booking.name, bill_to_email: booking.contact_email, bill_to_attention: booking.contact_name,
        issued_on: Date.current, due_on: booking.due_on, category_key: "tickets", production: listing.production, show: show,
        created_by: booking.created_by, pay_by_card: true, pay_by_bank: true, pay_by_check: true, reminders: "before_and_overdue",
        memo: "The seats are held for you until #{booking.release_on.strftime('%B %-d, %Y')}."
      )
      invoice.invoice_lines.build(description: "#{booking.seat_count} #{'seat'.pluralize(booking.seat_count)}, #{night}", quantity: booking.seat_count, unit_cents: booking.price_cents)
      invoice.invoice_lines.build(description: "#{booking.comp_count} chaperone #{'seat'.pluralize(booking.comp_count)}, no charge", quantity: booking.comp_count, unit_cents: 0) if booking.comp_count.positive?
      invoice.save!
      invoice
    end

    # The invoice was paid in full: the block becomes tickets, and a block
    # paid through our pay page costs the organization its 50¢ a seat.
    def self.invoice_paid!(booking, payment)
      return unless booking

      ticket!(booking) if booking.booked?
      fee!(booking) if payment&.via == "online"
    end

    # The block as one ticket order on the group's name, the leader's names
    # on the tickets in order, chaperones' seats free. The hold gives way to
    # the tickets in the same breath, so the seats are never counted twice
    # nor sold from under the group.
    def self.ticket!(booking, by: nil)
      return booking.ticket_order if booking.ticketed?
      raise Error, "This booking is #{booking.status_label.downcase}." unless booking.booked?

      listing = booking.ticket_listing
      tier = booking.ticket_tier
      names = booking.names_list
      order = nil
      ActiveRecord::Base.transaction do
        booking.quantity_hold&.release!
        Inventory.reserve!(listing, { tier => booking.seats }) do
          order = TicketOrder.create!(organization: listing.organization, ticket_listing: listing, status: "paid", paid_at: Time.current,
                                      channel: "group", money_path: "external", fee_mode: "org",
                                      buyer_name: booking.name, buyer_email: booking.contact_email, buyer_phone: booking.contact_phone,
                                      issued_by: by || booking.created_by, note: "Group booking: #{booking.contact_name}",
                                      refund_policy: RefundPolicy.for(listing).to_snapshot)
          booking.seats.times do |i|
            comp = i >= booking.seat_count
            order.tickets.create!(ticket_tier: tier, ticket_listing: listing, status: "valid", holder_name: names[i],
                                  price_cents: booking.price_cents, discount_cents: (comp ? booking.price_cents : 0))
          end
          TicketCheckout.price!(order)
          booking.update!(status: "ticketed", ticket_order: order, ticketed_at: Time.current)
        end
      end
      TicketSalesSync.sync!(listing.show)
      TicketGroupMailer.tickets_ready(booking).deliver_later
      order
    rescue Inventory::SoldOut
      raise Error, "The seats held for this group were sold from under it; check the date's seats before issuing."
    end

    # CocoScout's 50¢ a paid seat, out of the organization's balance, once.
    def self.fee!(booking)
      cents = FEE_CENTS * booking.seat_count
      return if cents.zero? || OrgCashEntry.exists?(source_type: "TicketGroupBooking", source_id: booking.id, entry_type: "ticket_sale")

      now = Time.current
      OrgCashEntry.post!(organization: booking.organization, entry_type: "ticket_sale", amount_cents: -cents, source: booking,
                         description: "CocoScout's fee on group tickets, #{booking.name}", occurred_at: now)
      LedgerPosting.post!(organization: booking.organization, source: booking, kind: "group_fee", entry_date: now.to_date, cash_date: now.to_date,
                          memo: "CocoScout's fee on group tickets, #{booking.name}",
                          lines: [ { account: :cocoscout_balance, amount_cents: -cents }, { account: :ticketing_fees, amount_cents: cents } ])
    end

    # The names the leader pasted, applied to the tickets once there are any.
    def self.name!(booking, names)
      booking.update!(names: names.to_s)
      return unless booking.ticketed? && booking.ticket_order

      list = booking.names_list
      booking.ticket_order.tickets.order(:id).each_with_index { |ticket, i| ticket.update_columns(holder_name: list[i], updated_at: Time.current) }
    end

    # Seats back on sale, invoice cancelled, leader told. canceled: the box
    # office called it off rather than the clock running out.
    def self.release!(booking, canceled: false, by: nil)
      return booking unless booking&.booked?

      booking.transaction do
        booking.update!(status: (canceled ? "canceled" : "released"), released_at: Time.current)
        booking.quantity_hold&.release!
        booking.invoice.void!(canceled ? "Group booking canceled" : "Seats released: not paid by #{booking.release_on.strftime('%b %-d')}") if booking.invoice&.open?
      end
      TicketGroupMailer.released(booking).deliver_later unless canceled && by
      WaitlistOfferJob.perform_later(booking.ticket_listing_id) if booking.ticket_listing.waitlist_entries.live.exists?
      booking
    end

    # The daily pass (GroupHoldReleaseJob): warn the leader a few days out,
    # release what wasn't paid in time.
    def self.sweep!(today = Date.current)
      TicketGroupBooking.booked.where(release_on: ...today).includes(:invoice, :quantity_hold, ticket_listing: :show).find_each { |b| release!(b) }
      TicketGroupBooking.booked.where(warned_at: nil).where(release_on: ..(today + TicketGroupBooking::WARNING_DAYS)).includes(:invoice, ticket_listing: :show).find_each do |booking|
        booking.update!(warned_at: Time.current)
        TicketGroupMailer.release_warning(booking).deliver_later
      end
    end
  end
end
