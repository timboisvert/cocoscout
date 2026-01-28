# frozen_string_literal: true

module Manage
  class TicketingProvidersController < Manage::ManageController
    before_action :set_ticketing_provider, only: [ :show, :edit, :update, :destroy, :test, :sync ]

    def index
      @providers = Current.organization.ticketing_providers.order(:name)
    end

    def show
      @sync_logs = @ticketing_provider.ticketing_sync_logs.recent.limit(10)
      @production_links = @ticketing_provider.ticketing_production_links.includes(:production)
    end

    def edit
      @provider_types = Ticketing::ServiceFactory.available_providers
    end

    def update
      if @ticketing_provider.update(ticketing_provider_params)
        redirect_to manage_ticketing_provider_path(@ticketing_provider), notice: "Provider updated."
      else
        @provider_types = Ticketing::ServiceFactory.available_providers
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name = @ticketing_provider.name
      @ticketing_provider.destroy
      redirect_to manage_ticketing_providers_path, notice: "#{name} disconnected."
    end

    def test
      result = Ticketing::SyncCoordinator.new(@ticketing_provider).test_connection

      if result[:success]
        @ticketing_provider.update(
          provider_account_name: result[:account_name],
          last_sync_error: nil
        )
        redirect_to manage_ticketing_provider_path(@ticketing_provider),
                    notice: "Connection successful! Found #{result[:event_count]} events."
      else
        @ticketing_provider.update(last_sync_error: result[:error])
        redirect_to manage_ticketing_provider_path(@ticketing_provider),
                    alert: "Connection failed: #{result[:error]}"
      end
    end

    def sync
      TicketingSyncJob.perform_later(@ticketing_provider.id)
      redirect_to manage_ticketing_provider_path(@ticketing_provider),
                  notice: "Sync started. This may take a moment."
    end

    private

    def set_ticketing_provider
      @ticketing_provider = Current.organization.ticketing_providers.find(params[:id])
    end

    def ticketing_provider_params
      params.require(:ticketing_provider).permit(
        :name,
        :provider_type,
        :api_key,
        :auto_sync_enabled,
        :sync_interval_minutes
      )
    end
  end
end
