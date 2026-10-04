# frozen_string_literal: true

module My
  # The ticket sales a theater shares with a producer or performer
  # (TicketSalesAccess): their shows and how each is selling, and one show
  # in full — sold of seats, sales, refunds, and the guest list as names
  # only. Nothing here can be changed, and no buyer's email ever shows.
  class TicketSalesController < ApplicationController
    before_action :require_authentication

    def index
      @show_my_sidebar = true
      listings = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location)
                                  .order("shows.date_and_time DESC").to_a
      now = Time.current.beginning_of_day
      @upcoming, @past = listings.partition { |l| l.show.date_and_time >= now }
      @upcoming.reverse!
      @stats = Ticketing::ListingStats.for(@upcoming.first(60) + @past.first(60))
      @daily_viewers = TicketSalesViewer.active.where(user_id: Current.user.id).to_a
      @daily_email = @daily_viewers.any?(&:daily_email)
    end

    def show
      @show_my_sidebar = true
      @listing = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location).find(params[:id])
      @stats = Ticketing::ListingStats.of(@listing)
      @guest_orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(:ticket_order_items, tickets: :ticket_tier)
                              .order(:buyer_name, :id).to_a.select { |o| o.tickets.any? { |t| Ticket::SOLD_STATUSES.include?(t.status) } }
    end

    # A morning email on how their shows are selling, on or off for every share they hold.
    def daily_email
      on = params[:daily_email] == "1"
      TicketSalesViewer.active.where(user_id: Current.user.id).update_all(daily_email: on, updated_at: Time.current)
      redirect_to my_ticket_sales_path, notice: on ? "You'll get a note each morning on how your shows are selling." : "No more daily emails."
    end
  end
end
