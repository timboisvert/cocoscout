# frozen_string_literal: true

module Manage
  # A production's ticket sales for its production team, in the Production
  # Dashboard (TicketSalesAccess levels, set in Ticketing settings → Who sees
  # sales): how each date is selling, one date's numbers and who's coming,
  # and comps within the team's allowance (Ticketing settings → Comps).
  # Deliberately not under /manage/ticketing and not in PaidFeatureGate's
  # FEATURE_BY_CONTROLLER: the Ticketing module stays the organization's
  # managers' (they're sent to it from here); this is the view a team gets by
  # role, gated here on Pro and an open box office.
  class ProductionSalesController < Manage::ManageController
    include GivesComps

    before_action :set_production
    before_action :check_production_access
    before_action :require_sales_level!
    before_action :set_listing, only: %i[show create_comp preview_comps]

    def index
      @filter = params[:dates] == "past" ? "past" : "upcoming"
      scope = live_listings.includes(:ticket_tiers, show: %i[location location_space])
      @listings = if @filter == "past"
        scope.where("shows.date_and_time < ?", Time.current).order("shows.date_and_time DESC").limit(100).to_a
      else
        scope.where("shows.date_and_time >= ?", Time.current).order("shows.date_and_time").to_a
      end
      @stats = Ticketing::ListingStats.for(@listings)
      # The link buyers use: this production's own, or the seller's page for
      # the production these dates belong to.
      @link_url = short_link_url(code: ShortLink.canonical_for!(@sold_elsewhere ? (@listings.first&.production || @production) : @production).code)
    end

    def show
      @stats = Ticketing::ListingStats.of(@listing)
      @link = TicketLink.for(@listing.show, listing: @listing)
      return unless @level == :full

      @guest_orders = @listing.ticket_orders.where(status: TicketOrder::WAS_PAID).includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass bundle_tier])
                              .order(:buyer_name, :id).to_a.select { |o| o.tickets.any? { |t| Ticket::SOLD_STATUSES.include?(t.status) } }
      @allowance = TicketSalesAccess.comp_allowance(Current.user, @listing)
    end

    # A comp from a production team manager, within their allowance; the
    # same form as the manager's (GivesComps).
    def create_comp
      give_comp_within_allowance(@listing, TicketSalesAccess.comp_allowance(Current.user, @listing), back: sale_path)
    end

    # A pasted list's preview, within the same allowance.
    def preview_comps
      preview_comps_within_allowance(@listing, TicketSalesAccess.comp_allowance(Current.user, @listing))
    end

    private

    # Scoped to the current org: a bare find here would reach another org's production.
    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    # This production's own dates on sale. When its dates follow another
    # organization's contract (LinkedDates), the tickets are that
    # organization's: its listings for those dates, read through the link
    # and nothing else of theirs (LinkedTicketSales).
    def live_listings
      return LinkedTicketSales.listings_for_production(@production) if @sold_elsewhere

      Current.organization.ticket_listings.where(production: @production).where.not(status: %w[draft canceled])
             .joins(:show).where(shows: { canceled: false })
    end

    def set_listing
      @listing = live_listings.includes(:production, show: :location).find(params[:id])
    end

    def sale_path
      manage_production_sale_path(@production, @listing, anchor: "guests")
    end

    # What this user sees by role (TicketSalesAccess): Pro, box office open,
    # and a production team manager or viewer whom Who sees sales lets in.
    # The organization's managers have the whole module, so they go there.
    def require_sales_level!
      # Dates that follow another organization's contract: that organization
      # sells the tickets, and this page is the window onto them, for this
      # organization's managers too (they have no Ticketing for these dates).
      @seller = LinkedTicketSales.connections_for_production(@production).select { |connection| LinkedTicketSales.sharing?(connection) }.first&.organization
      if @seller
        @sold_elsewhere = true
        @level = LinkedTicketSales.production_level(Current.user, @production)
        return if @level

        return redirect_to(manage_production_path(@production), notice: "Ticket sales for #{@production.name} aren't shared with you.")
      end

      # Connected, but the seller has stopped sharing its sales: say so,
      # and never send anyone on to set up a box office for dates that
      # another organization sells.
      unshared = LinkedTicketSales.connections_for_production(@production).first&.organization
      if unshared && @production.tickets_mode != "cocoscout"
        return redirect_to(manage_production_path(@production),
                           notice: "#{unshared.name} sells the tickets for these dates, and isn't sharing its ticket sales for this contract right now.")
      end

      if Current.user.superadmin? || Current.organization.manageable_by?(Current.user)
        return redirect_to(manage_production_ticketing_path(@production))
      end

      @level = TicketSalesAccess.team_level_for(Current.user, @production)
      return if @level

      redirect_to manage_production_path(@production), notice: "Ticket sales for #{@production.name} aren't shared with you."
    end
  end
end
