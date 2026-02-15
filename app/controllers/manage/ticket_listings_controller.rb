# frozen_string_literal: true

module Manage
  class TicketListingsController < Manage::ManageController
    before_action :set_production
    before_action :set_show
    before_action :set_show_ticketing
    before_action :set_listing, only: %i[show edit update destroy publish sync]

    def index
      @listings = @show_ticketing.ticket_listings.includes(:ticketing_provider)
    end

    def show
      @offers = @listing.ticket_offers.includes(:show_ticket_tier)
      @recent_sales = @listing.ticket_sales.recent.limit(20)
    end

    def new
      @listing = @show_ticketing.ticket_listings.build
      @providers = Current.organization.ticketing_providers.status_active
      @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
    end

    def create
      @listing = @show_ticketing.ticket_listings.build(listing_params)

      if @listing.save
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          notice: "Listing created."
      else
        @providers = Current.organization.ticketing_providers.status_active
        @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @providers = Current.organization.ticketing_providers.status_active
      @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
    end

    def update
      if @listing.update(listing_params)
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          notice: "Listing updated."
      else
        @providers = Current.organization.ticketing_providers.status_active
        @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @listing.ticket_sales.exists?
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          alert: "Cannot delete listing with existing sales."
      else
        @listing.destroy
        redirect_to manage_ticket_listings_path(@production, @show),
          notice: "Listing deleted."
      end
    end

    def publish
      result = @listing.publish!

      if result[:success]
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          notice: "Listing published to #{@listing.provider_name}."
      else
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          alert: "Failed to publish: #{result[:error]}"
      end
    end

    def sync
      result = @listing.sync!

      if result[:success]
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          notice: "Listing synced successfully."
      else
        redirect_to manage_ticket_listing_path(@production, @show, @listing),
          alert: "Sync failed: #{result[:error]}"
      end
    end

    private

    def set_production
      @production = Current.user.accessible_productions.find(params[:production_id])
      # Ensure production has ticketing enabled
      unless @production.ticketing_enabled?
        redirect_to manage_ticketing_index_path, alert: "Ticketing is not enabled for this production."
      end
    end

    def set_show
      @show = @production.shows.find(params[:show_id])
    end

    def set_show_ticketing
      @show_ticketing = @show.show_ticketing
      redirect_to manage_setup_show_ticketing_path(@production, @show) unless @show_ticketing
    end

    def set_listing
      @listing = @show_ticketing.ticket_listings.find(params[:id])
    end

    def listing_params
      params.require(:ticket_listing).permit(
        :ticketing_provider_id,
        :status,
        ticket_offers_attributes: %i[
          id show_ticket_tier_id name description quantity
          seats_per_offer price_cents status _destroy
        ]
      )
    end
  end
end
