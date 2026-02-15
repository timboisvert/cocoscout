# frozen_string_literal: true

module Manage
  class TicketingProvidersController < Manage::ManageController
    before_action :set_provider, only: %i[show edit update destroy test_connection sync]

    def index
      @providers = Current.organization.ticketing_providers.order(:name)
    end

    def show
      @recent_listings = @provider.ticket_listings.includes(show_ticketing: :show).order(created_at: :desc).limit(10)
      @recent_sync_errors = @provider.ticket_listings.where.not(sync_errors: nil).limit(5)
      @sync_rules = @provider.ticket_sync_rules.active
    end

    def new
      @provider = Current.organization.ticketing_providers.build
    end

    def create
      @provider = Current.organization.ticketing_providers.build(provider_params)

      if @provider.save
        redirect_to manage_ticketing_provider_path(@provider), notice: "Ticketing provider created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @provider.update(provider_params)
        redirect_to manage_ticketing_provider_path(@provider), notice: "Ticketing provider updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @provider.ticket_listings.exists?
        redirect_to manage_ticketing_providers_path, alert: "Cannot delete provider with existing listings."
      else
        @provider.destroy
        redirect_to manage_ticketing_providers_path, notice: "Ticketing provider deleted."
      end
    end

    def test_connection
      result = @provider.test_connection

      if result[:success]
        redirect_to manage_ticketing_provider_path(@provider), notice: "Connection successful!"
      else
        redirect_to manage_ticketing_provider_path(@provider), alert: "Connection failed: #{result[:error]}"
      end
    end

    def sync
      # Sync all active listings for this provider
      @provider.ticket_listings.active.find_each(&:sync!)

      redirect_to manage_ticketing_provider_path(@provider), notice: "Sync initiated for all active listings."
    end

    private

    def set_provider
      @provider = Current.organization.ticketing_providers.find(params[:id])
    end

    def provider_params
      params.require(:ticketing_provider).permit(
        :name,
        :provider_type,
        :status,
        :api_key,
        :api_secret,
        :webhook_secret
      )
    end
  end
end
