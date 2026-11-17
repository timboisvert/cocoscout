# frozen_string_literal: true

module My
  # One date's ticket sales for someone a theater shares them with, or who
  # is on the date's contract (TicketSalesAccess): sold of seats, sales,
  # refunds, and the guest list as names only. It is a sub-page of the show
  # (/my/shows/:id/tickets), reached from the show's own page; there is no
  # list of them and nothing in the My menu (Tim, 2026-10-17 and 2026-11-17).
  # Nothing here can be changed, and no buyer's email ever shows, except
  # that someone on a contract that includes the date gives comps for their
  # own show (TicketSalesAccess.comp_allowance).
  class TicketSalesController < ApplicationController
    include GivesComps

    before_action :require_authentication
    before_action :set_listing, only: %i[show create_comp preview_comps daily_email]

    # A link to the old page for one listing (/my/ticket-sales/:id): on to
    # the show's own.
    def moved
      listing = TicketSalesAccess.listings_for(Current.user).find(params[:id])
      redirect_to my_show_tickets_path(listing.show_id), status: :moved_permanently
    end

    def show
      @show_my_sidebar = true
      @stats = Ticketing::ListingStats.of(@listing)
      @allowance = TicketSalesAccess.comp_allowance(Current.user, @listing)
      # Whether the show's own page is theirs to open (it is by contract or
      # by being in the show; a share alone gives only this page).
      @show_page = @listing.show if TicketSalesAccess.on_contract_for?(Current.user, @listing)
      @daily_email = TicketSalesViewer.active.where(user_id: Current.user.id, daily_email: true).exists?
      @guest_orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass bundle_tier])
                              .order(:buyer_name, :id).to_a.select { |o| o.tickets.any? { |t| Ticket::SOLD_STATUSES.include?(t.status) } }
    end

    # A comp from someone on the date's contract, within what the date can
    # still give away; the same form as the manager's.
    def create_comp
      give_comp_within_allowance(@listing, TicketSalesAccess.comp_allowance(Current.user, @listing),
                                 back: my_show_tickets_path(@listing.show_id, anchor: "guests"))
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
      redirect_to my_show_tickets_path(@listing.show_id), notice: on ? "You'll get a note each morning on how your shows are selling." : "No more daily emails."
    end

    private

    def set_listing
      @listing = TicketSalesAccess.listings_for(Current.user).includes(:organization, :production, show: :location).find_by!(show_id: params[:id])
    end
  end
end
