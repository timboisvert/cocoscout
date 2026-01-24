# frozen_string_literal: true

module Manage
  class TicketingProductionLinksController < Manage::ManageController
    before_action :set_production
    before_action :set_ticketing_production_link, only: [ :show, :edit, :update, :destroy, :sync, :match, :apply_matches ]

    def index
      @ticketing_production_links = @production.ticketing_production_links.includes(:ticketing_provider)
      @available_providers = Current.organization.ticketing_providers.enabled
    end

    def show
      @show_links = @ticketing_production_link.ticketing_show_links
                                               .includes(:show)
                                               .order("shows.date_and_time DESC")
      @unlinked_shows = @ticketing_production_link.unlinked_shows
                                                   .where("date_and_time >= ?", 30.days.ago)
                                                   .order(:date_and_time)
    end

    def new
      @ticketing_production_link = @production.ticketing_production_links.build
      @providers = Current.organization.ticketing_providers.enabled

      if @providers.empty?
        redirect_to manage_ticketing_providers_path,
                    alert: "Connect a ticketing platform first before linking a production."
        return
      end

      # If provider is pre-selected, fetch available events
      if params[:provider_id].present?
        @provider = @providers.find(params[:provider_id])
        @available_events = fetch_available_events(@provider)
      end
    end

    def create
      @ticketing_production_link = @production.ticketing_production_links.build(ticketing_production_link_params)

      if @ticketing_production_link.save
        # Auto-match shows
        matcher = Ticketing::Operations::MatchShows.new(@ticketing_production_link)
        result = matcher.auto_match!

        if result[:applied] > 0
          redirect_to manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                      notice: "Production linked! #{result[:applied]} shows matched automatically."
        else
          redirect_to match_manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                      notice: "Production linked. Match shows to start syncing."
        end
      else
        @providers = Current.organization.ticketing_providers.enabled
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @provider = @ticketing_production_link.ticketing_provider
    end

    def update
      if @ticketing_production_link.update(ticketing_production_link_params)
        redirect_to manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                    notice: "Ticketing settings updated."
      else
        @provider = @ticketing_production_link.ticketing_provider
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @ticketing_production_link.destroy
      redirect_to manage_money_ticketing_production_links_path(@production),
                  notice: "Ticketing integration removed."
    end

    def sync
      result = Ticketing::Operations::ImportSales.new(@ticketing_production_link, user: Current.user).call

      if result[:success]
        redirect_to manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                    notice: "Sync complete! #{result[:records_updated]} shows updated."
      else
        redirect_to manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                    alert: "Sync failed: #{result[:error]}"
      end
    end

    def match
      @matcher = Ticketing::Operations::MatchShows.new(@ticketing_production_link)
      @analysis = @matcher.analyze
    end

    def apply_matches
      match_params = params[:matches] || []

      # Build match data from form
      matches = match_params.map do |m|
        {
          show_id: m[:show_id],
          occurrence_id: m[:occurrence_id]
        }
      end.select { |m| m[:occurrence_id].present? }

      if matches.any?
        matcher = Ticketing::Operations::MatchShows.new(@ticketing_production_link)
        applied = matcher.apply_matches!(matches)

        redirect_to manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                    notice: "#{applied} shows matched."
      else
        redirect_to match_manage_money_ticketing_production_link_path(@production, @ticketing_production_link),
                    alert: "No matches selected."
      end
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_ticketing_production_link
      @ticketing_production_link = @production.ticketing_production_links.find(params[:id])
    end

    def ticketing_production_link_params
      params.require(:ticketing_production_link).permit(
        :ticketing_provider_id,
        :provider_event_id,
        :provider_event_name,
        :provider_event_url,
        :sync_ticket_sales,
        :sync_enabled
      )
    end

    def fetch_available_events(provider)
      coordinator = Ticketing::SyncCoordinator.new(provider)
      coordinator.fetch_available_events
    rescue => e
      Rails.logger.error("Failed to fetch events: #{e.message}")
      []
    end
  end
end
