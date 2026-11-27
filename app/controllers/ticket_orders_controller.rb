# frozen_string_literal: true

# A buyer's order and tickets, at a private link (/tickets/orders/<token>) — the one
# in their confirmation email. No account needed: the token is the key, and it
# names exactly one order.
class TicketOrdersController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  # The token is the key, and the embed has no session cookie (see
  # TicketCheckoutsController). Mail apps' one-click unsubscribe posts
  # straight to stop_reminders.
  skip_forgery_protection only: %i[resend stop_reminders add_deal]

  before_action :set_order

  def show
    @deals = TicketCheckout.deals_after(@order)
  end

  # A receipt for a sale at the door, paid or not (Apple's Tap to Pay 5.10:
  # the buyer can have one either way): who sold it, what, how much, when,
  # and whether it was paid. The door shows it as a QR code to scan.
  def receipt
  end

  # Taking a deal on another show after paying: a new checkout at the deal
  # price, remembering this purchase (TicketCheckout.start_deal!).
  def add_deal
    offer = @order.organization.ticket_offers.find(params[:offer])
    new_order = TicketCheckout.start_deal!(order: @order, offer: offer, quantity: params[:quantity])
    redirect_to tickets_checkout_path(token: new_order.token, **embed_params)
  rescue TicketCheckout::Error => e
    redirect_to tickets_order_path(token: @order.token, anchor: "deals", **embed_params), alert: e.message
  end

  # "Add to calendar": the show as a one-event .ics file.
  def calendar
    show = @listing.show
    ics = Ticketing::Calendar.ics([ {
      uid: "ticket-order-#{@order.code}@cocoscout.com", starts: show.date_and_time, ends: @listing.ends_at || (show.date_and_time + 2.hours),
      summary: @listing.display_title, location: Ticketing::Calendar.place(show),
      description: "Your tickets: #{tickets_order_url(token: @order.token)}"
    } ])
    send_data ics, filename: "#{@listing.slug}.ics", type: "text/calendar"
  end

  # "Download tickets (PDF)": every ticket on the order, a page each
  # (TicketPdf). Small enough to draw on the request, like an invoice.
  def pdf
    document = TicketPdf.new(@order)
    unless @order.paid? && document.tickets?
      return redirect_to tickets_order_path(token: @order.token, **embed_params), alert: "This order has no tickets to download."
    end

    send_data document.render, filename: TicketPdf.filename(@order), type: "application/pdf", disposition: "attachment"
  end

  def resend
    TicketOrderConfirmationJob.perform_later(@order.id) if @order.paid? && @order.buyer_email.present?
    redirect_to tickets_order_path(token: @order.token, **embed_params), notice: "We've sent your tickets to #{@order.buyer_email} again."
  end

  # From the reminder email's "Stop reminder emails" link: a page with one
  # button, so a mail scanner opening the link changes nothing.
  def reminders; end

  def stop_reminders
    @order.update!(reminders_opt_out: true)
    redirect_to tickets_order_path(token: @order.token, **embed_params),
                notice: "You won't get reminder emails for this order.", status: :see_other
  end

  # A refund offered when the organization moved the date, or canceled it
  # and moved the tickets to another date (DateChange): the buyer's own, any
  # time before the show starts. A page with one button, so a mail scanner
  # opening the link changes nothing.
  def date_change_refund
    @change = refund_offer_change
  end

  def date_change_refund_issue
    @change = refund_offer_change
    unless @change && refund_offer_open?
      return redirect_to tickets_date_change_refund_path(token: @order.token, change_id: params[:change_id], **embed_params), status: :see_other
    end

    refund = TicketOrderRefund.issue!(@order, reason: "Requested after the date changed", notify: true, outside_policy: true, reprice: false)
    @change.with_lock do
      list = Array(@change.summary["buyer_refunds"]) + [ { "order_id" => @order.id, "name" => @order.buyer_name, "cents" => refund.amount_cents, "at" => Time.current.iso8601 } ]
      @change.update_columns(summary: @change.summary.merge("buyer_refunds" => list))
    end
    redirect_to tickets_order_path(token: @order.token, **embed_params), status: :see_other,
                notice: "Refunded #{ActiveSupport::NumberHelper.number_to_currency(refund.amount_cents / 100.0)}. #{TicketOrderMailer.refund_where_words(refund)}"
  rescue TicketOrderRefund::Error => e
    redirect_to tickets_date_change_refund_path(token: @order.token, change_id: params[:change_id], **embed_params), alert: e.message, status: :see_other
  end

  private

  def refund_offer_change
    change = DateChange.applied.find_by(id: params[:change_id], organization_id: @listing.organization_id)
    return nil unless change

    offered = change.move? && change.on?(:buyers_refund_offer) && change.all_show_ids.include?(@listing.show_id)
    offered ||= change.cancel? && Array(change.undo["rebooked_order_ids"]).map(&:to_i).include?(@order.id)
    offered ? change : nil
  end

  helper_method :refund_offer_open?
  def refund_offer_open?
    @order.paid? && @order.money_path != "none" && !@listing.show.canceled? && @listing.show.date_and_time > Time.current
  end

  def set_order
    @order = TicketOrder.includes(tickets: :ticket_tier, ticket_listing: [ :organization, :production, { show: %i[location location_space] } ])
                        .find_by!(token: params[:token])
    @listing = @order.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
    # The order wears the date's page colors, as its ticket page and checkout do.
    @page_colors = PageColors.for(@ticketing_profile, @listing.production_ticketing, @listing)
    use_time_zone_of(@listing.organization)
  end
end
