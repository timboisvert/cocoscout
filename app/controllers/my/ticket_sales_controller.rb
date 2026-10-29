# frozen_string_literal: true

module My
  # The ticket sales a theater shares with a producer or performer
  # (TicketSalesAccess): their shows and how each is selling, and one show
  # in full — sold of seats, sales, refunds, and the guest list as names
  # only. Nothing here can be changed, and no buyer's email ever shows,
  # except that someone on a contract that includes the date gives comps for
  # their own show (TicketSalesAccess.comp_allowance).
  class TicketSalesController < ApplicationController
    include GivesComps

    before_action :require_authentication
    before_action :set_listing, only: %i[show create_comp preview_comps]

    UPCOMING_BATCH = 30
    PAST_PER_PAGE = 30

    # What's selling now: the next dates first, "Show more" for the next
    # batch, and the past a page at a time. Figures only for the rows shown.
    def index
      @show_my_sidebar = true
      listings = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location)
      now = Time.current.beginning_of_day
      upcoming = listings.where("shows.date_and_time >= ?", now).order("shows.date_and_time ASC, ticket_listings.id ASC")
      @upcoming_shown = params[:upcoming].to_i.clamp(UPCOMING_BATCH, 10_000)
      @upcoming = upcoming.limit(@upcoming_shown + 1).to_a
      @more_upcoming = @upcoming.size > @upcoming_shown
      @upcoming = @upcoming.first(@upcoming_shown)
      @pagy, @past = pagy(listings.where("shows.date_and_time < ?", now).order("shows.date_and_time DESC, ticket_listings.id DESC"),
                          limit: PAST_PER_PAGE, page_key: "past_page")
      @stats = Ticketing::ListingStats.for(@upcoming + @past)
      @sees_sales = @upcoming.any? || @pagy.count.positive?
      @daily_email = TicketSalesViewer.active.where(user_id: Current.user.id, daily_email: true).exists?
    end

    def show
      @show_my_sidebar = true
      @stats = Ticketing::ListingStats.of(@listing)
      @allowance = TicketSalesAccess.comp_allowance(Current.user, @listing)
      @guest_orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass bundle_tier])
                              .order(:buyer_name, :id).to_a.select { |o| o.tickets.any? { |t| Ticket::SOLD_STATUSES.include?(t.status) } }
    end

    # A comp from someone on the date's contract, within what the date can
    # still give away; the same form as the manager's.
    def create_comp
      give_comp_within_allowance(@listing, TicketSalesAccess.comp_allowance(Current.user, @listing),
                                 back: my_ticket_sale_path(@listing, anchor: "guests"))
    end

    # A pasted list's preview, within the same allowance.
    def preview_comps
      preview_comps_within_allowance(@listing, TicketSalesAccess.comp_allowance(Current.user, @listing))
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

    private

    def set_listing
      @listing = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location).find(params[:id])
    end
  end
end
