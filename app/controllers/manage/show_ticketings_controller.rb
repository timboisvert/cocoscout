# frozen_string_literal: true

module Manage
  class ShowTicketingsController < Manage::ManageController
    before_action :set_production, except: :index
    before_action :set_show, only: %i[show setup create_setup edit update sync]
    before_action :set_show_ticketing, only: %i[show edit update sync]

    def index
      # Show all productions with upcoming shows that have ticketing enabled
      @productions = Current.user.accessible_productions
        .includes(:shows, :contract)
        .order(:name)
        .select { |p| p.ticketing_enabled? && p.shows.upcoming.any? }
    end

    def production
      # Show all shows for a production with their ticketing status
      @shows = @production.shows.upcoming.order(:date_and_time)
      @show_ticketings = ShowTicketing.where(show_id: @shows.pluck(:id)).index_by(&:show_id)
    end

    def show
      @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
      @listings = @show_ticketing.ticket_listings.includes(:ticketing_provider)
      @recent_sales = TicketSale.joins(ticket_offer: :ticket_listing)
        .where(ticket_listings: { show_ticketing_id: @show_ticketing.id })
        .order(purchased_at: :desc)
        .limit(10)
    end

    def setup
      # Set up ticketing for a show
      @seating_configurations = Current.organization.seating_configurations.order(:name)
      @show_ticketing = ShowTicketing.new(show: @show)

      # Pre-select configuration if location matches
      if @show.location_id.present?
        matching_config = @seating_configurations.find_by(location_id: @show.location_id)
        @show_ticketing.seating_configuration = matching_config if matching_config
      end
    end

    def create_setup
      @show_ticketing = ShowTicketing.new(setup_params.merge(show: @show))

      if @show_ticketing.save
        # Copy tiers from seating configuration
        @show_ticketing.copy_tiers_from_configuration!

        redirect_to manage_show_ticketing_path(@production, @show), notice: "Ticketing set up successfully."
      else
        @seating_configurations = Current.organization.seating_configurations.order(:name)
        render :setup, status: :unprocessable_entity
      end
    end

    def edit
      @seating_configurations = Current.organization.seating_configurations.order(:name)
    end

    def update
      if @show_ticketing.update(update_params)
        redirect_to manage_show_ticketing_path(@production, @show), notice: "Ticketing updated."
      else
        @seating_configurations = Current.organization.seating_configurations.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def sync
      # Sync all listings for this show
      @show_ticketing.ticket_listings.active.find_each(&:sync!)

      redirect_to manage_show_ticketing_path(@production, @show), notice: "Sync initiated."
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
      @show_ticketing = ShowTicketing.find_by!(show: @show)
    end

    def setup_params
      params.require(:show_ticketing).permit(
        :seating_configuration_id,
        :total_capacity,
        :total_available
      )
    end

    def update_params
      params.require(:show_ticketing).permit(
        :total_capacity,
        :total_available,
        :total_held
      )
    end
  end
end
