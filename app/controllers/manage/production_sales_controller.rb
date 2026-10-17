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
    before_action :set_production
    before_action :check_production_access
    before_action :require_sales_level!
    before_action :set_listing, only: %i[show create_comp]

    def index
      @filter = params[:dates] == "past" ? "past" : "upcoming"
      scope = live_listings.includes(:ticket_tiers, show: %i[location location_space])
      @listings = if @filter == "past"
        scope.where("shows.date_and_time < ?", Time.current).order("shows.date_and_time DESC").limit(100).to_a
      else
        scope.where("shows.date_and_time >= ?", Time.current).order("shows.date_and_time").to_a
      end
      @stats = Ticketing::ListingStats.for(@listings)
      @link_url = short_link_url(code: ShortLink.canonical_for!(@production).code)
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
    # same form as the manager's (Manage::TicketCompsController#create).
    def create_comp
      allowance = TicketSalesAccess.comp_allowance(Current.user, @listing)
      unless allowance && (allowance[:left].nil? || allowance[:left].positive?)
        return redirect_to(sale_path, alert: "You can't give comps for this date.")
      end

      quantity = params[:quantity].to_i
      if allowance[:left] && quantity > allowance[:left]
        return redirect_to(sale_path, alert: "You can give #{helpers.pluralize(allowance[:left], 'more comp')} for this date.")
      end

      tier = @listing.ticket_tiers.active.find { |t| t.id == params[:tier_id].to_i }
      email = params[:email].to_s.strip.downcase.presence
      email_them = params[:email_them] == "1"
      if email_them && email.blank?
        return redirect_to(sale_path, alert: "Add their email to send their tickets, or switch off Email them their tickets.")
      end

      guest = TicketComps::Guest.new(name: params[:name].to_s.squish, email: email, tier: tier, quantity: quantity)
      order = TicketComps.give!(@listing, [ guest ], by: Current.user, note: params[:note], email_them: email_them).sole
      redirect_to sale_path, notice: "Gave #{helpers.pluralize(order.tickets.size, 'ticket')} to #{guest.name}. They're on the list."
    rescue TicketComps::Error => e
      redirect_to sale_path, alert: e.message
    end

    private

    # Scoped to the current org: a bare find here would reach another org's production.
    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def live_listings
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
      if Current.user.superadmin? || Current.organization.manageable_by?(Current.user)
        return redirect_to(manage_production_ticketing_path(@production))
      end

      @level = TicketSalesAccess.team_level_for(Current.user, @production)
      return if @level

      redirect_to manage_production_path(@production), notice: "Ticket sales for #{@production.name} aren't shared with you."
    end
  end
end
