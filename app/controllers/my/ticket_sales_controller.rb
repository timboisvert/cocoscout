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
      @sees_sales = listings.any?
      @daily_email = TicketSalesViewer.active.where(user_id: Current.user.id, daily_email: true).exists?
    end

    def show
      @show_my_sidebar = true
      @listing = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location).find(params[:id])
      @stats = Ticketing::ListingStats.of(@listing)
      @guest_orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass])
                              .order(:buyer_name, :id).to_a.select { |o| o.tickets.any? { |t| Ticket::SOLD_STATUSES.include?(t.status) } }
    end

    # A morning email on how their shows are selling, on or off for every
    # share they hold. A producer who sees sales only through a contract has
    # no share row, so one is made for each of those productions to hold
    # the choice.
    def daily_email
      on = params[:daily_email] == "1"
      TicketSalesAccess.contract_productions(Current.user).each do |production|
        TicketSalesViewer.active.find_or_create_by!(organization: production.organization, user: Current.user, scope: production) do |viewer|
          viewer.accepted_at = Time.current
        end
      end
      TicketSalesViewer.active.where(user_id: Current.user.id).update_all(daily_email: on, updated_at: Time.current)
      redirect_to my_ticket_sales_path, notice: on ? "You'll get a note each morning on how your shows are selling." : "No more daily emails."
    end
  end
end
