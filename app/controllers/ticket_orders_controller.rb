# frozen_string_literal: true

# A buyer's order and tickets, at a private link (/t/orders/<token>) — the one
# in their confirmation email. No account needed: the token is the key, and it
# names exactly one order.
class TicketOrdersController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  # The token is the key, and the embed has no session cookie (see
  # TicketCheckoutsController). Mail apps' one-click unsubscribe posts
  # straight to stop_reminders.
  skip_forgery_protection only: %i[resend stop_reminders]

  before_action :set_order

  def show; end

  # "Add to calendar": the show as a one-event .ics file.
  def calendar
    show = @listing.show
    starts = show.date_and_time.utc
    ends = (@listing.ends_at || (show.date_and_time + 2.hours)).utc
    stamp = ->(time) { time.strftime("%Y%m%dT%H%M%SZ") }
    escape = ->(text) { text.to_s.gsub(/[\\;,]/) { |c| "\\#{c}" }.gsub("\n", "\\n") }
    place = [ show.location&.name, show.location&.address1, show.location&.city ].compact_blank.join(", ")
    ics = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CocoScout//Tickets//EN", "BEGIN:VEVENT",
      "UID:ticket-order-#{@order.code}@cocoscout.com", "DTSTAMP:#{stamp.call(Time.current.utc)}",
      "DTSTART:#{stamp.call(starts)}", "DTEND:#{stamp.call(ends)}",
      "SUMMARY:#{escape.call(@listing.display_title)}", "LOCATION:#{escape.call(place)}",
      "DESCRIPTION:#{escape.call("Your tickets: #{tickets_order_url(token: @order.token)}")}",
      "END:VEVENT", "END:VCALENDAR"
    ].join("\r\n")
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
