# frozen_string_literal: true

module Manage
  # Giving tickets away from a show's page (TicketComps): names and emails,
  # typed or pasted, one ticket type, and each guest gets their tickets.
  class TicketCompsController < Manage::TicketingBaseController
    before_action :set_listing

    def new
      @tier_id = (@tiers.find { |t| t.price_cents.zero? } || @tiers.first)&.id
    end

    def create
      tier = @tiers.find { |t| t.id == params[:tier_id].to_i }
      guests = TicketComps.parse(params[:guests], listing: @listing, default_tier: tier)
      orders = TicketComps.give!(@listing, guests, by: Current.user, note: params[:note], email_them: params[:email_them] == "1")
      count = orders.sum { |order| order.tickets.size }
      redirect_to manage_ticket_listing_path(@listing, anchor: "guests"),
                  notice: "Gave #{helpers.pluralize(count, 'ticket')} to #{helpers.pluralize(orders.size, 'person')}."
    rescue TicketComps::Error => e
      @guests_text = params[:guests]
      @tier_id = tier&.id
      @note = params[:note]
      @email_them = params[:email_them] == "1"
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    private

    # Scoped to the current org: a bare find here would reach another org's show.
    def set_listing
      @listing = Current.organization.ticket_listings.find(params[:id])
      @tiers = @listing.ticket_tiers.active.to_a
    end
  end
end
