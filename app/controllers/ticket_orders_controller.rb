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

  private

  def set_order
    @order = TicketOrder.includes(tickets: :ticket_tier, ticket_listing: [ :organization, :production, { show: %i[location location_space] } ])
                        .find_by!(token: params[:token])
    @listing = @order.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
  end
end
